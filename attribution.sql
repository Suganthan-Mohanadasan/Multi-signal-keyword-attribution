-- ============================================================
-- Multi-Signal Keyword Revenue Attribution
-- ============================================================
-- 3-signal join:        page + date + device
-- Intent weighting:     branded > transactional > commercial > navigational > informational
-- Renormalisation:      per page, sum of attributed metrics matches the GA4 page total
-- Confidence:           HIGH / MEDIUM / LOW based on candidates per page and click volume
--
-- A note on country. GSC stores country as an ISO 3166-1 alpha-3 code ('usa', 'gbr')
-- while GA4 geo.country stores a full English name ('United States'). They cannot be
-- joined directly, so this query narrows on page + date + device only. If you want a
-- country signal too, map GA4's names to alpha-3 in a CTE first, then add it back to
-- the join keys.
--
-- Setup
--   1. Find/replace the two placeholders below with your dataset names:
--        <<GSC_DATASET>>   e.g. searchconsole
--        <<GA4_DATASET>>   e.g. analytics_123456789
--   2. Edit the DECLARE block to fit your brand, intent rules, and conversion events.
--   3. Run the whole script in BigQuery (Standard SQL).
--
-- Output columns
--   query, page, intent, clicks,
--   att_sessions, att_conversions, att_revenue,
--   candidates_on_page, avg_competitors_per_bucket, confidence
-- ============================================================


-- ============================================================
-- Configurable parameters
-- ============================================================

-- ------------------------------------------------------------
-- BRAND MATCHING (3 tiers, lowercase everything)
-- ------------------------------------------------------------
-- Tier 1: brand_terms (REQUIRED)
--   Substring match. Use canonical brand forms a user would type:
--     ['snippet digital', 'snippetdigital']
--     ['uk models', 'ukmodels']
-- Tier 2: brand_tokens + brand_min_token_matches (OPTIONAL, recommended for multi-word brands)
--   Stem-prefix matching with word boundary. Each token matches the start
--   of any word, so 'model' catches 'models', 'modelling', 'modeling',
--   'modeler'. A query is branded if it contains at least
--   brand_min_token_matches distinct tokens.
--     brand_tokens=['uk','model'], min=2 catches:
--       "model uk", "uk modelling", "models uk", "uk modeling agency"
--   Leave empty ([]) to skip tier 2.
-- Tier 3: brand_negative_terms (OPTIONAL, false-positive guard)
--   If any of these substrings match, query is NEVER branded, overriding
--   tiers 1 and 2. Use for ambiguous single-word brands like "Apple":
--     ['apple pie', 'apple cider', 'apple fruit']
--   Leave empty ([]) if your brand isn't ambiguous.

DECLARE brand_terms ARRAY<STRING> DEFAULT ['mybrand', 'my brand'];
DECLARE brand_tokens ARRAY<STRING> DEFAULT [];
DECLARE brand_min_token_matches INT64 DEFAULT 2;
DECLARE brand_negative_terms ARRAY<STRING> DEFAULT [];

-- Window
DECLARE days INT64 DEFAULT 28;
DECLARE min_clicks INT64 DEFAULT 5;

-- Optional: imputed value per conversion when GA4 has no monetary value
-- Leave at 0 to use GA4 revenue as is. Set to e.g. 499.0 for a fixed lead value.
DECLARE value_per_conversion FLOAT64 DEFAULT 0.0;

-- Intent weights
DECLARE w_branded FLOAT64 DEFAULT 3.0;
DECLARE w_transactional FLOAT64 DEFAULT 2.0;
DECLARE w_commercial FLOAT64 DEFAULT 1.5;
DECLARE w_navigational FLOAT64 DEFAULT 1.0;
DECLARE w_informational FLOAT64 DEFAULT 0.5;

-- Intent regex (edit to match your vocabulary)
DECLARE re_transactional STRING DEFAULT r'\b(buy|prices?|pricing|demo|signup|sign[- ]?up|order|trial|quote)\b';
DECLARE re_commercial STRING DEFAULT r'\b(best|top|reviews?|compares?|comparison|alternatives?|vs)\b';
DECLARE re_navigational STRING DEFAULT r'\b(login|sign[- ]?in|contacts?|hours|address|phone)\b';

-- GA4 conversion event names (modify to match your tracking)
DECLARE conversion_events ARRAY<STRING> DEFAULT ['form_submit', 'generate_lead', 'purchase'];

-- Date range. GSC has ~3 day lag; we cap end_date at today minus 3 days.
DECLARE end_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY);
DECLARE start_date DATE DEFAULT DATE_SUB(end_date, INTERVAL days - 1 DAY);


-- ============================================================
-- Pipeline
-- ============================================================

WITH

-- 1. GSC: clicks per query x page x date x device
gsc AS (
  SELECT
    LOWER(query) AS query,
    LOWER(REGEXP_REPLACE(REGEXP_REPLACE(url, r'\?.*$', ''), r'/$', '')) AS page_norm,
    data_date,
    LOWER(device) AS device,
    SUM(clicks) AS clicks,
    SUM(impressions) AS impressions
  FROM `<<GSC_DATASET>>.searchdata_url_impression`
  WHERE data_date BETWEEN start_date AND end_date
    AND query IS NOT NULL
    AND query != ''
    AND UPPER(search_type) = 'WEB'
    AND clicks > 0
  GROUP BY query, page_norm, data_date, device
),

-- 2. GA4: extract per-event attributes for organic-search sessions
ga4_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    PARSE_DATE('%Y%m%d', event_date) AS data_date,
    LOWER(device.category) AS device,
    LOWER(REGEXP_REPLACE(REGEXP_REPLACE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'\?.*$', ''), r'/$', '')) AS page_url,
    event_name,
    event_timestamp,
    -- Event-level medium, auto-populated by GA4 on page_view events. It is absent on
    -- session_start / first_visit before 2023-11-02, so we coalesce across events below.
    -- Newer exports also expose this without UNNEST via session_traffic_source_last_click.
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    -- revenue: prefer ecommerce.purchase_revenue, fall back to event_params.value
    COALESCE(
      IF(event_name = 'purchase', ecommerce.purchase_revenue, NULL),
      (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value'),
      0
    ) AS event_value
  FROM `<<GA4_DATASET>>.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', start_date) AND FORMAT_DATE('%Y%m%d', end_date)
),

-- 3. GA4: collapse events to sessions
--    session_medium = the medium reported on session_start, fallback to any
ga4_sessions AS (
  SELECT
    user_pseudo_id,
    session_id,
    ANY_VALUE(data_date) AS data_date,
    ANY_VALUE(device) AS device,
    ARRAY_AGG(page_url IGNORE NULLS ORDER BY event_timestamp ASC LIMIT 1)[OFFSET(0)] AS landing_page,
    COALESCE(
      ANY_VALUE(IF(event_name = 'session_start', medium, NULL)),
      ANY_VALUE(medium)
    ) AS session_medium,
    COUNTIF(event_name IN UNNEST(conversion_events)) AS conversions,
    SUM(IF(event_name IN UNNEST(conversion_events), event_value, 0)) AS revenue
  FROM ga4_events
  WHERE session_id IS NOT NULL
  GROUP BY user_pseudo_id, session_id
),

-- 4. GA4: aggregate organic-search sessions to page x date x device
--    Adjust the LOWER(session_medium) filter if your GA4 setup uses different
--    traffic-source values (e.g. "Organic Search" channel grouping).
ga4 AS (
  SELECT
    landing_page AS page_norm,
    data_date,
    device,
    COUNT(*) AS sessions,
    SUM(conversions) AS conversions,
    SUM(revenue) AS revenue
  FROM ga4_sessions
  WHERE landing_page IS NOT NULL
    AND LOWER(session_medium) = 'organic'
  GROUP BY landing_page, data_date, device
),

-- 5. GSC: classify intent (3-tier brand matching)
--    Tier 3 (negative) overrides everything.
--    Tier 1 (substring) is the fast path.
--    Tier 2 (stem-prefix tokens, count >= min) catches variations.
gsc_classified AS (
  SELECT
    *,
    CASE
      -- Tier 3: negative override (forces non-brand)
      WHEN ARRAY_LENGTH(brand_negative_terms) > 0
           AND EXISTS (SELECT 1 FROM UNNEST(brand_negative_terms) nt WHERE STRPOS(query, LOWER(nt)) > 0)
        THEN
          CASE
            WHEN REGEXP_CONTAINS(query, re_transactional) THEN 'transactional'
            WHEN REGEXP_CONTAINS(query, re_commercial) THEN 'commercial'
            WHEN REGEXP_CONTAINS(query, re_navigational) THEN 'navigational'
            ELSE 'informational'
          END
      -- Tier 1: substring brand match
      WHEN EXISTS (SELECT 1 FROM UNNEST(brand_terms) bt WHERE STRPOS(query, LOWER(bt)) > 0)
        THEN 'branded'
      -- Tier 2: token-prefix brand match (only if tokens are configured)
      WHEN ARRAY_LENGTH(brand_tokens) > 0
           AND (
             SELECT COUNT(DISTINCT bt)
             FROM UNNEST(brand_tokens) bt
             WHERE REGEXP_CONTAINS(query, CONCAT(r'\b', LOWER(bt)))
           ) >= brand_min_token_matches
        THEN 'branded'
      WHEN REGEXP_CONTAINS(query, re_transactional) THEN 'transactional'
      WHEN REGEXP_CONTAINS(query, re_commercial) THEN 'commercial'
      WHEN REGEXP_CONTAINS(query, re_navigational) THEN 'navigational'
      ELSE 'informational'
    END AS intent
  FROM gsc
),

gsc_weighted AS (
  SELECT
    *,
    CASE intent
      WHEN 'branded' THEN w_branded
      WHEN 'transactional' THEN w_transactional
      WHEN 'commercial' THEN w_commercial
      WHEN 'navigational' THEN w_navigational
      ELSE w_informational
    END AS intent_weight,
    clicks * (CASE intent
      WHEN 'branded' THEN w_branded
      WHEN 'transactional' THEN w_transactional
      WHEN 'commercial' THEN w_commercial
      WHEN 'navigational' THEN w_navigational
      ELSE w_informational
    END) AS weighted_clicks
  FROM gsc_classified
),

-- 6. Bucket totals: weighted clicks and competitor count per (page, date, device)
bucket_totals AS (
  SELECT
    page_norm, data_date, device,
    SUM(weighted_clicks) AS bucket_weighted_clicks,
    COUNT(DISTINCT query) AS bucket_query_count
  FROM gsc_weighted
  GROUP BY page_norm, data_date, device
),

-- 7. Bucket-level attribution: distribute GA4 metrics by weighted click share
attributed_buckets AS (
  SELECT
    g.query,
    g.page_norm,
    g.data_date,
    g.device,
    g.intent,
    g.clicks,
    SAFE_DIVIDE(g.weighted_clicks, b.bucket_weighted_clicks) * COALESCE(a.sessions, 0) AS att_sessions_raw,
    SAFE_DIVIDE(g.weighted_clicks, b.bucket_weighted_clicks) * COALESCE(a.conversions, 0) AS att_conversions_raw,
    SAFE_DIVIDE(g.weighted_clicks, b.bucket_weighted_clicks) * COALESCE(a.revenue, 0) AS att_revenue_raw,
    b.bucket_query_count
  FROM gsc_weighted g
  JOIN bucket_totals b USING (page_norm, data_date, device)
  LEFT JOIN ga4 a USING (page_norm, data_date, device)
),

-- 8. Aggregate to (query, page) and filter by min_clicks
query_page AS (
  SELECT
    query,
    page_norm,
    ANY_VALUE(intent) AS intent,
    SUM(clicks) AS total_clicks,
    SUM(att_sessions_raw) AS att_sessions_raw,
    SUM(att_conversions_raw) AS att_conversions_raw,
    SUM(att_revenue_raw) AS att_revenue_raw,
    AVG(bucket_query_count) AS avg_competitors_per_bucket
  FROM attributed_buckets
  GROUP BY query, page_norm
  HAVING SUM(clicks) >= min_clicks
),

-- 9. Per-page totals of kept queries (used for renormalisation)
page_kept_totals AS (
  SELECT
    page_norm,
    SUM(att_sessions_raw) AS page_kept_sessions,
    SUM(att_conversions_raw) AS page_kept_conversions,
    SUM(att_revenue_raw) AS page_kept_revenue,
    COUNT(DISTINCT query) AS candidates_on_page
  FROM query_page
  GROUP BY page_norm
),

-- 10. Per-page totals from GA4 (target for renormalisation)
ga4_page_totals AS (
  SELECT
    page_norm,
    SUM(sessions) AS page_total_sessions,
    SUM(conversions) AS page_total_conversions,
    SUM(revenue) AS page_total_revenue
  FROM ga4
  GROUP BY page_norm
)


-- ============================================================
-- Final output
-- ============================================================
SELECT
  qp.query,
  qp.page_norm AS page,
  qp.intent,
  qp.total_clicks AS clicks,
  -- renormalise so each page's kept-query attribution sums to the GA4 page total
  ROUND(qp.att_sessions_raw * SAFE_DIVIDE(COALESCE(gpt.page_total_sessions, pkt.page_kept_sessions), NULLIF(pkt.page_kept_sessions, 0)), 2) AS att_sessions,
  ROUND(qp.att_conversions_raw * SAFE_DIVIDE(COALESCE(gpt.page_total_conversions, pkt.page_kept_conversions), NULLIF(pkt.page_kept_conversions, 0)), 4) AS att_conversions,
  -- revenue: use GA4 revenue if present, else fall back to imputed value_per_conversion
  ROUND(
    GREATEST(
      qp.att_revenue_raw * SAFE_DIVIDE(COALESCE(gpt.page_total_revenue, pkt.page_kept_revenue), NULLIF(pkt.page_kept_revenue, 0)),
      qp.att_conversions_raw * SAFE_DIVIDE(COALESCE(gpt.page_total_conversions, pkt.page_kept_conversions), NULLIF(pkt.page_kept_conversions, 0)) * value_per_conversion
    ), 2) AS att_revenue,
  pkt.candidates_on_page,
  ROUND(qp.avg_competitors_per_bucket, 1) AS avg_competitors_per_bucket,
  CASE
    WHEN pkt.candidates_on_page <= 3 AND qp.total_clicks >= 10 THEN 'HIGH'
    WHEN pkt.candidates_on_page >= 11 OR qp.total_clicks < 5 THEN 'LOW'
    ELSE 'MEDIUM'
  END AS confidence
FROM query_page qp
JOIN page_kept_totals pkt USING (page_norm)
LEFT JOIN ga4_page_totals gpt USING (page_norm)
ORDER BY att_revenue DESC, att_conversions DESC, att_sessions DESC;
