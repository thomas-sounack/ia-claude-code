---
description: Profile the CDC datasets and report what's in them
---

Profile the two CSV datasets in `cdc_data/` so we understand what we're working
with before building anything. Do NOT build the app yet — just investigate and
report back.

For **each** dataset, find and report:

1. Row count and column count.
2. The list of columns (they should match between the two files — confirm this).
3. For the key columns we'll likely visualize:
   - `state_territory` — how many distinct states/territories?
   - `sample_collect_date` — the earliest and latest dates.
   - `pcr_target_detect` — the breakdown of yes vs no.
   - `population_served` and `pcr_target_avg_conc_lin` — rough value ranges.
4. **Data quality issues** that will bite us when loading:
   - Are numbers stored with comma thousands-separators (e.g. `"13,000"`)?
   - Which columns use `-1` or blanks as "not reported" sentinels?
   - Anything else surprising.

Prefer quick command-line inspection (e.g. `head`, `wc -l`, a short Python
snippet with pandas) over loading everything into memory repeatedly. Watch out:
because numeric fields contain commas inside quotes, naive `cut`/`awk` on commas
will split fields incorrectly — pandas with `thousands=','` is more reliable.

End with a short, plain-English summary: "Here's what these datasets contain and
here's what we need to clean before plotting."
