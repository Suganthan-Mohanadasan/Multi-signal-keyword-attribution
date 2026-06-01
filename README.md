# Multi-Signal Keyword Attribution

A free, open skill for the "(not provided)" gap in Google Analytics. It estimates which of your visible Search Console queries are driving GA4 conversions and revenue, joining the two inside BigQuery with 3-signal narrowing, intent weighting, and a confidence score on every row.

> **Full guide with setup walkthrough:** [suganthan.com/blog/not-provided-keywords-google-analytics/](https://suganthan.com/blog/not-provided-keywords-google-analytics/)

## What it does

For each Google Search Console query that brought clicks to your site, this skill tells you how many GA4 sessions, conversions, and revenue that specific query is responsible for, and how confident you should be in the answer.

The methodology:

1. **Joins GSC and GA4 on 3 signals**: normalised landing page, date, device.
2. **Distributes GA4 metrics within each (page, date, device) bucket** by weighted click share.
3. **Weights by search intent**: branded (3.0x), transactional (2.0x), commercial (1.5x), navigational (1.0x), informational (0.5x).
4. **Renormalises per page** so the sum of attributed metrics matches GA4's actual page total.
5. **Scores confidence per row** based on candidate count and click volume.

## Example output

You get a sortable table of every query, the page it landed on, its intent, and the GA4 sessions, conversions, and revenue attributed to it, each with a confidence rating. Here is a condensed sample (synthetic SaaS site, 28-day window, numbers illustrative):

| Query | Page | Intent | Clicks | Att. Conv | Att. Revenue | Confidence |
|---|---|---|---|---|---|---|
| projectflow pricing | /pricing | branded | 168 | 28.4 | $6,820 | HIGH |
| projectflow | / | branded | 412 | 41.6 | $9,985 | LOW |
| best project management software | /comparison | commercial | 218 | 7.2 | $1,180 | MEDIUM |
| buy project management software | /pricing | transactional | 45 | 5.1 | $640 | HIGH |
| what is a kanban board | /blog/kanban-explained | informational | 412 | 0.9 | $48 | HIGH |

The confidence column is the part the paid black-box tools do not show you. `projectflow` pulls the most clicks but scores LOW because 19 queries compete for the home page, so the $9,985 beside it is the least trustworthy number in the table. `projectflow pricing` pulls fewer than half the clicks but scores HIGH because the pricing page has only 6 candidate queries. Sort by confidence, trust the HIGH rows, treat the LOW rows as directional.

The intent split usually tells the real story. In this dataset branded queries drove 70% of revenue on 23% of clicks, while informational queries drove 1.3% of revenue on 42% of clicks. That is the ROI gap on top-of-funnel content, made visible. Full worked example in [examples/synthetic_saas_demo.md](examples/synthetic_saas_demo.md).

## Why this approach

| | Native GA4 + GSC link | Looker Studio blend | Keyword Hero | This skill |
|---|---|---|---|---|
| Cost | Free | Free | Free, then $9 to $149/mo | Free |
| Methodology | Read-only report | Page-level uniform | Black box ML | 3-signal + intent + confidence |
| Confidence per row | None | None | None shown | HIGH/MEDIUM/LOW |
| Source visibility | N/A | N/A | Closed | Open SQL |
| Data ownership | N/A | Yours | Theirs | Yours |

You can read the methodology. You can verify the SQL. You can adjust the multipliers. Every assumption is visible in a `DECLARE` block at the top of `attribution.sql`.

## Requirements

- Google Search Console bulk export to BigQuery (the `searchconsole` dataset).
- GA4 BigQuery export linked, daily or streaming.
- A BigQuery service account with read access on both datasets.
- For Claude Code users: the [BigQuery MCP server](https://github.com/Suganthan-Mohanadasan/Suganthans-BigQuery-MCP-Server) connected.

## Quick start (BigQuery only)

1. Open `attribution.sql` in the BigQuery console.
2. Find/replace `<<GSC_DATASET>>` and `<<GA4_DATASET>>` with your actual dataset names.
3. Edit the `DECLARE` block: `brand_terms`, `brand_tokens`, `days`, `min_clicks`, optionally `value_per_conversion`.
4. Run. Takes 1 to 3 minutes on a typical site (around $0.05 in BigQuery costs per run).

## Quick start (Claude Code)

Clone into your skills directory:

```bash
git clone https://github.com/Suganthan-Mohanadasan/multi-signal-keyword-attribution.git ~/.claude/skills/multi-signal-attribution
```

Then in Claude with the BigQuery MCP server connected:

```
Run a multi-signal keyword revenue attribution on my data.
Brand terms: ['mybrand', 'mybranddotcom']
Brand tokens: ['my', 'brand']
GSC dataset: searchconsole
GA4 dataset: analytics_XXXXXXXXX
```

## Brand matching

The skill uses 3 tiers for brand classification. Get this right or branded queries get misclassified as informational and their attributed revenue gets deflated.

**Tier 1: `brand_terms`** (required) - substring match on canonical brand forms.

**Tier 2: `brand_tokens` + `brand_min_token_matches`** (optional, recommended for multi-word brands) - stem-prefix matching with word boundary. The token `'model'` catches `'models'`, `'modelling'`, `'modeling'`, `'modeler'`. A query is branded if it contains at least `brand_min_token_matches` distinct tokens.

**Tier 3: `brand_negative_terms`** (optional, false-positive guard) - if any of these substrings match, the query is never branded. For ambiguous single-word brands like Apple.

### Worked examples

| Brand | Tier 1 | Tier 2 | Min | Tier 3 |
|---|---|---|---|---|
| Coca-Cola | `['coca cola', 'cocacola', 'coke']` | `['coca', 'cola']` | 2 | `[]` |
| Snippet Digital | `['snippet digital', 'snippetdigital']` | `['snippet', 'digital']` | 2 | `[]` |
| Apple (company) | `['apple']` | `[]` | 0 | `['apple pie', 'apple cider']` |
| Stripe (payments) | `['stripe']` | `[]` | 0 | `['pin stripe', 'stripe pattern']` |

If branded-looking queries show up as informational in your output, the fix is almost always adding tier 2 tokens.

## Tuning

Three things matter most for accuracy:

1. **Brand matching.** See above.
2. **Conversion event names.** Default is `['form_submit', 'generate_lead', 'purchase']`. Update to match what you have in GA4. Run a discovery query first to see your event names.
3. **Intent regex.** Defaults are tuned for B2B / lead-gen. For ecommerce, lift `transactional` weight to 2.5 to 3.0 and add words like `cheap`, `discount`, `coupon` to the regex.

## Caveats

- GSC has a ~3 day lag. The date window defaults to `today - 3 days` back.
- GSC anonymises low-volume queries. Ahrefs put it at roughly 46% of organic clicks on average, varying from a couple of percent to over 90% by site. The skill cannot attribute revenue to those, so your real organic revenue is always higher than the attributed total.
- GSC uses Pacific Time. GA4 uses your property timezone. Expect ~5% noise on day boundaries.
- The 3-signal join rate is typically 70 to 90% by clicks. Sessions outside the join are not attributed.
- Renormalisation spreads each page's full GA4 total across only the visible queries. Revenue that really came from anonymised or unmatched queries on that page gets redistributed onto the visible ones, so the per-query split is a best estimate. Page-level totals stay correct.
- Confidence is a heuristic, not a statistical confidence interval. HIGH means signal alignment is strong and the candidate set is small.
- Lead-gen sites without monetary conversion values can use `value_per_conversion` to impute revenue from a fixed lead value.

## Licence

MIT. See [LICENSE](LICENSE).

If you find it useful, star the repo. Pull requests welcome.
