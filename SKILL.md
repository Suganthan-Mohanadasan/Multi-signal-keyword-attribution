---
name: multi-signal-attribution
description: >
  Multi-signal keyword revenue attribution combining GSC bulk export and GA4 export
  in BigQuery. Runs a 3-signal join (page + date + device), applies
  intent weighting (branded, transactional, commercial, navigational, informational),
  renormalises per landing page so query-level attribution sums to the GA4 page
  total, and scores confidence per row. Use this skill whenever the user wants to:
  attribute GA4 sessions, conversions, or revenue to specific GSC queries; find
  which keywords drive money (not just clicks); compute revenue per keyword;
  run keyword-level attribution; cross-join GSC and GA4 in BigQuery; understand
  which queries on a page actually convert. Trigger on phrases like "attribute
  revenue to keywords", "which keywords drive conversions", "GSC plus GA4
  attribution", "revenue per query", "keyword level revenue", "what drives
  conversions on this page". Requires the BigQuery MCP server and a project
  containing both the GSC bulk export dataset and the GA4 events export.
---

# Multi-Signal Keyword Revenue Attribution

You are running a keyword-level revenue attribution analysis using GSC bulk export and GA4 export data, both in BigQuery. The output is a sortable markdown table of (query, page, intent, clicks, attributed sessions, attributed conversions, attributed revenue, confidence) plus a short headline summary.

## When to use

Trigger this skill whenever the user wants to know which queries are driving traffic value (sessions, conversions, revenue) rather than just clicks. The methodology pushes attribution one level finer than the standard `ga4_gsc_query_revenue` MCP tool because it joins on three signals (page + date + device) before distributing GA4 metrics, applies intent weighting so branded and transactional queries get more credit than informational, and renormalises so totals match GA4 exactly.

If the user only wants click share or a one-line answer like "what keywords does my site rank for", use `ahrefs-quick-lookup` or the prebuilt `ga4_gsc_query_revenue` tool instead.

## Required inputs

Ask for whichever of these are missing. Default to the values shown if the user does not specify.

| Parameter | Default | Notes |
|---|---|---|
| `brand_terms` | required | Lowercase array. Tier 1 substring match. Use canonical brand forms (e.g. `['snippet digital', 'snippetdigital']`). |
| `brand_tokens` | `[]` | Lowercase array. Tier 2 stem-prefix tokens. Each token matches the start of any word, so `'model'` catches `'models'`, `'modelling'`, `'modeling'`. Recommended for any multi-word brand to catch word-order and stem variations. |
| `brand_min_token_matches` | 2 | How many tokens from `brand_tokens` must appear in a query for it to be branded. 2 is the right default for 2-word brands. |
| `brand_negative_terms` | `[]` | Lowercase array. Tier 3 false-positive guard. Any query containing one of these is NEVER branded. Use for ambiguous single-word brands (e.g. `['apple pie', 'apple cider']` for Apple). |
| `gsc_dataset` | required | The dataset holding `searchdata_url_impression`, e.g. `searchconsole`. |
| `ga4_dataset` | required | The GA4 export dataset, e.g. `analytics_123456789`. |
| `days` | 28 | Days back from today minus 3 (GSC has a ~3 day lag). |
| `min_clicks` | 5 | Drop queries with fewer total clicks across the window. |
| `value_per_conversion` | 0.0 | Optional fixed lead value if GA4 has no monetary value. Set to e.g. 499.0 for a fixed conversion value. |
| `conversion_events` | `['form_submit', 'generate_lead', 'purchase']` | GA4 event names to count as conversions. |

Intent weights and intent regex are configurable too (see DECLARE block in `attribution.sql`). The defaults are tuned for B2B / lead-gen sites; transactional weight may want bumping up to 2.5 for ecommerce.

### Brand matching: how to fill it in

When asking the user for brand terms, ask for both tiers explicitly:

> "What's your brand? Give me 1) the exact phrases people type for you (e.g. 'snippet digital', 'snippetdigital'), and 2) the unique words in your brand to match as stems (e.g. 'snippet', 'digital')."

For most multi-word brands, tier 2 should contain the same words as tier 1 split into individual tokens. Examples:

| Brand | brand_terms (tier 1) | brand_tokens (tier 2) | min |
|---|---|---|---|
| Coca-Cola | `['coca cola', 'cocacola', 'coke']` | `['coca', 'cola']` | 2 |
| Snippet Digital | `['snippet digital', 'snippetdigital']` | `['snippet', 'digital']` | 2 |
| UK Models | `['uk models', 'ukmodels']` | `['uk', 'model']` | 2 |
| Keyword Insights | `['keyword insights', 'keywordinsights']` | `['keyword', 'insights']` | 2 |

For single-word brands (Apple, Notion, Stripe), tier 2 is usually unnecessary. Use tier 3 to exclude false positives instead:

| Brand | brand_terms (tier 1) | brand_negative_terms (tier 3) |
|---|---|---|
| Apple (the company) | `['apple']` | `['apple pie', 'apple cider', 'apple fruit']` |
| Stripe (payments) | `['stripe']` | `['pin stripe', 'stripe pattern']` |

If the user reports that obvious brand-adjacent queries are being classified as informational (e.g. plurals or word-order variations falling through), the fix is almost always adding tier 2 tokens.

## Procedure

1. **Confirm the inputs.** If brand_terms, gsc_dataset, or ga4_dataset are missing, ask the user. Explicitly confirm any unusual values (e.g. days > 90, min_clicks > 25).

2. **Probe both datasets exist.** Before running the full query, run two cheap probes via the BigQuery MCP `query` tool:
   - `SELECT MAX(data_date) FROM \`{gsc_dataset}.searchdata_url_impression\``
   - `SELECT MAX(_TABLE_SUFFIX) FROM \`{ga4_dataset}.events_*\``
   If either errors, surface the exact error to the user and stop. Do not proceed with the main query.

3. **Run the attribution query.** Use the BigQuery MCP `query` tool with the SQL in `attribution.sql`, after substituting `<<GSC_DATASET>>` and `<<GA4_DATASET>>` with the user's dataset names. Update the DECLARE block to reflect the user's brand_terms, days, min_clicks, value_per_conversion, and conversion_events. Set `max_rows` to 200 to capture the long tail.

4. **Render the output.** Format the result as a markdown table sorted by attributed revenue descending. Columns: query, page, intent, clicks, att_sessions, att_conversions, att_revenue (with currency symbol), candidates_on_page, confidence. After the table, write:
   - A 2-3 sentence headline summarising total clicks, sessions, conversions, revenue, and the branded share.
   - Top 3 high-confidence drivers (single line each).
   - Any patterns worth flagging (e.g. all HIGH-confidence pages with zero conversions, intent splits that look unusual, brand variations being missed by the substring rule).

5. **Optionally render the visual artifact.** If the user asks for a dashboard, snapshot, or screenshot, build an inline HTML widget using the `show_widget` MCP tool. The widget should include: 4 metric cards (clicks, sessions, conversions, revenue), a horizontal bar chart of top 12 queries by attributed revenue color-coded by intent, a stacked bar of intent split (clicks vs sessions vs revenue), and a sortable filterable table.

## Common pitfalls and what to do

- **Brand terms missed by the substring rule.** "uk model" does not contain "uk models". Always proactively fuzz the brand list: include singular/plural, with and without spaces, common typos, internal job titles. If you see informational queries on the home page outranking branded ones in raw clicks, it is almost always a missing brand variation.
- **Revenue is zero everywhere.** This means GA4 is not populating `ecommerce.purchase_revenue` or `event_params.value`. For lead-gen sites this is normal. Either accept conversions as the success metric, or pass `value_per_conversion` so revenue is imputed as `conversions x value`.
- **All confidence ratings are LOW because everything is on the home page.** This is a legitimate finding, not a bug. The home page genuinely has too many candidate queries to attribute cleanly. Flag it as a structural finding ("internal links and topic-specific landing pages would split this attribution into deterministic chunks") rather than trying to game the score.
- **Join rate seems low.** GSC and GA4 normalise URLs differently (trailing slashes, query strings, fragments). The SQL strips trailing slashes and query strings on both sides; if the join rate is still under 50%, check for protocol mismatches (http vs https) or hostname differences (www vs non-www).
- **GA4 organic filter excludes too much.** The SQL filters to sessions where any event reports `medium=organic`. If the user's GA4 setup uses different traffic source values (e.g. `Organic Search` as the channel grouping), edit the WHERE clause in the `ga4_sessions` CTE.
- **GSC dataset is in one project, GA4 in another.** BigQuery cross-project queries work fine; just fully qualify both placeholders, e.g. `project-a.searchconsole`, `project-b.analytics_123456789`. The MCP service account needs read access on both.

## Output format example

```
## [domain] keyword revenue attribution, last 28 days

**Window:** 2026-04-01 to 2026-04-28
**Brand terms:** "..." | **Min clicks:** 5

| Query | Page | Intent | Clicks | Att. Sessions | Att. Conv | Att. Revenue | Confidence |
|---|---|---|---|---|---|---|---|
| ... | ... | branded | 280 | 263.4 | 19.96 | £9,960 | HIGH |

Headline: 903 clicks, 697 attributed sessions, 39 conversions, £19,461 revenue. Branded captures 86% of conversions on 57% of clicks.

Top 3 high-confidence drivers
1. ...
2. ...
3. ...

Patterns
- ...
- ...
```

## Files in this skill

- `attribution.sql`: the parameterised query
- `SKILL.md`: this file
- `examples/synthetic_saas_demo.md`: a worked example output for reference
