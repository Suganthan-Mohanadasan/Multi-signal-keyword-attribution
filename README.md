# Multi-Signal Keyword Attribution

A free skill that solves the "(not provided)" problem in Google Analytics. Joins your GA4 conversion data with Search Console keyword data inside BigQuery using 4-signal narrowing, intent weighting, and confidence scoring per row.

> **Full guide with setup walkthrough:** [suganthan.com/blog/not-provided-keywords-google-analytics/](https://suganthan.com/blog/not-provided-keywords-google-analytics/)

## What it does

For each Google Search Console query that brought clicks to your site, this skill tells you how many GA4 sessions, conversions, and revenue that specific query is responsible for, and how confident you should be in the answer.

The methodology:

1. **Joins GSC and GA4 on 4 signals**: normalised landing page, date, device, country.
2. **Distributes GA4 metrics within each (page, date, device, country) bucket** by weighted click share.
3. **Weights by search intent**: branded (3.0x), transactional (2.0x), commercial (1.5x), navigational (1.0x), informational (0.5x).
4. **Renormalises per page** so the sum of attributed metrics matches GA4's actual page total.
5. **Scores confidence per row** based on candidate count and click volume.

## Why this approach

| | Native GA4 + GSC link | Looker Studio blend | Keyword Hero | This skill |
|---|---|---|---|---|
| Cost | Free | Free | $9 to $99/mo | Free |
| Methodology | Read-only report | Page-level uniform | Black box ML | 4-signal + intent + confidence |
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
- GSC anonymises low-volume queries. Around 30 to 50% of organic clicks come back as `is_anonymized_query = true`. The skill cannot attribute revenue to those.
- GSC uses Pacific Time. GA4 uses your property timezone. Expect ~5% noise on day boundaries.
- The 4-signal join rate is typically 70 to 90% by clicks. Sessions outside the join are not attributed.
- Confidence is a heuristic, not a statistical confidence interval. HIGH means signal alignment is strong and the candidate set is small.
- Lead-gen sites without monetary conversion values can use `value_per_conversion` to impute revenue from a fixed lead value.

## Licence

MIT. See [LICENSE](LICENSE).

If you find it useful, star the repo. Pull requests welcome.
