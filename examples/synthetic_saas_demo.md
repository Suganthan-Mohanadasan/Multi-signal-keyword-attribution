# Synthetic demo output

This is what the skill returns when you run it on a typical mid-sized SaaS site. The site is a hypothetical project management tool called ProjectFlow with a mix of branded, commercial, and informational queries. Real GA4 ecommerce events (subscription purchases, trial signups). Real GSC bulk export.

This output is fabricated for documentation purposes. Numbers are realistic but not from a real account.

## Configuration used

| Parameter | Value |
|---|---|
| `brand_terms` | `['projectflow', 'project flow']` |
| `brand_tokens` | `['project', 'flow']` |
| `brand_min_token_matches` | `2` |
| `brand_negative_terms` | `[]` |
| `days` | `28` |
| `min_clicks` | `5` |
| `value_per_conversion` | `0.0` (GA4 already has purchase_revenue populated) |
| `conversion_events` | `['trial_start', 'subscription_purchase', 'signup']` |

## Output

### Headline

**3,847 clicks, 2,891 attributed sessions, 217 attributed conversions, $48,920 attributed revenue across 76 query/page rows.**

By intent:
- Branded: 134.2 conv / 1,124 sess / 892 clicks → $34,210 revenue (70% of revenue on 23% of clicks)
- Commercial: 38.7 conv / 612 sess / 1,103 clicks → $9,840 revenue
- Transactional: 22.4 conv / 287 sess / 245 clicks → $4,210 revenue
- Informational: 21.7 conv / 868 sess / 1,607 clicks → $660 revenue (1.3% of revenue on 42% of clicks)

### Attribution table (top 20 by attributed revenue)

| Query | Page | Intent | Clicks | Att. Sessions | Att. Conv | Att. Revenue | Confidence |
|---|---|---|---|---|---|---|---|
| projectflow | / | branded | 412 | 387.2 | 41.6 | $9,985 | LOW |
| projectflow pricing | /pricing | branded | 168 | 152.8 | 28.4 | $6,820 | HIGH |
| project flow software | / | branded | 96 | 89.7 | 9.6 | $2,310 | LOW |
| projectflow review | /reviews | branded | 84 | 78.1 | 8.2 | $1,975 | HIGH |
| project flow alternative | /vs/notion | branded | 71 | 64.5 | 6.8 | $1,640 | HIGH |
| projectflow vs notion | /vs/notion | branded | 68 | 61.8 | 6.5 | $1,560 | HIGH |
| projectflow login | /login | branded | 142 | 128.9 | 5.4 | $1,290 | HIGH |
| best project management software | /comparison | commercial | 218 | 168.4 | 7.2 | $1,180 | MEDIUM |
| project flow demo | / | branded | 42 | 39.4 | 4.8 | $1,150 | LOW |
| projectflow free trial | /signup | branded | 38 | 35.6 | 4.6 | $1,105 | HIGH |
| trello alternatives | /vs/trello | commercial | 156 | 124.2 | 5.1 | $945 | MEDIUM |
| asana vs projectflow | /vs/asana | branded | 51 | 47.8 | 3.9 | $940 | HIGH |
| project management for startups | /use-cases/startups | commercial | 142 | 108.7 | 4.2 | $890 | HIGH |
| notion alternatives | /vs/notion | commercial | 184 | 142.6 | 3.8 | $830 | MEDIUM |
| best agile tools | /comparison | commercial | 96 | 78.3 | 2.9 | $710 | MEDIUM |
| buy project management software | /pricing | transactional | 45 | 41.2 | 5.1 | $640 | HIGH |
| project management software pricing | /pricing | transactional | 89 | 81.6 | 4.8 | $580 | HIGH |
| projectflow careers | /careers | branded | 24 | 22.1 | 0.4 | $96 | HIGH |
| how to manage projects | /blog/manage-projects | informational | 287 | 168.4 | 1.2 | $58 | HIGH |
| what is a kanban board | /blog/kanban-explained | informational | 412 | 248.7 | 0.9 | $48 | HIGH |

(56 more rows omitted — full output would include all queries with 5+ clicks)

### Top 3 high-confidence revenue drivers

1. **projectflow pricing** → /pricing, branded, 168 clicks → 28.4 conversions, $6,820 revenue, HIGH. The pricing page has 6 candidate queries this period and "projectflow pricing" dominates the click share. Clearest revenue attribution in the dataset.
2. **projectflow review** → /reviews, branded, 84 clicks → 8.2 conversions, $1,975 revenue, HIGH. Single dominant query on the page.
3. **buy project management software** → /pricing, transactional, 45 clicks → 5.1 conversions, $640 revenue, HIGH. 2.0x intent weight on a high-conversion page makes this rank above queries with more raw clicks.

### Patterns and surprises

1. **Informational queries are 42% of clicks but 1.3% of revenue.** "what is a kanban board" pulled 412 clicks and attributed less than $50. This is the actual ROI gap on top-of-funnel content. Useful to know before committing more resources to that cluster.
2. **The home page is a bottleneck.** "projectflow" alone pulled 412 clicks but landed at LOW confidence because the home page has 19 candidate queries competing. Splitting branded variations onto dedicated landing pages (login, pricing, vs/* pages already do this) would convert LOW rows to HIGH.
3. **Commercial queries are punching above their weight.** "best project management software" generated $1,180 from 218 clicks — that's $5.41 per click attributed, higher than several branded queries. Worth doubling down on the /comparison page content.

### Caveat for this dataset

Anonymised queries account for 38% of total clicks in the GSC bulk export for this 28-day window. Their revenue contribution is not attributed to specific queries. The visible 62% of clicks generated the $48,920 attributed in the table; the actual revenue from organic search will be higher than this number suggests.
