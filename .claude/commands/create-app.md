---
description: Build the initial Streamlit dashboard app.py from scratch
---

Build the initial version of `app.py` — a single-page Streamlit dashboard for
the CDC wastewater surveillance data. Follow every rule in `CLAUDE.md`.

## What to build

1. **Data loading** — a single `@st.cache_data` function that reads both CSVs
   from `cdc_data/` and returns one combined DataFrame with a `pathogen` column.
   Apply all the known data-quality fixes on load:
   - `thousands=','` so numeric fields parse correctly.
   - Replace `-1` and blanks with `NaN` in sentinel columns (`flow_rate`,
     `rec_eff_percent`, `rec_eff_spike_conc`).
   - Parse `sample_collect_date` as datetime.

2. **Sidebar controls** — at minimum:
   - Pathogen selector (Avian Influenza A (H5) / Measles / Both).
   - State/territory multi-select (derive the list from the data).
   - Date-range slider (derive min/max from the data).

3. **Main area** — at minimum two charts using Plotly rendered with
   `st.plotly_chart(use_container_width=True)`:
   - **Detection rate over time** — line or bar chart of the fraction of samples
     where `pcr_target_detect == "yes"`, grouped by week or month.
   - **Concentration over time** — scatter or line chart of
     `pcr_target_avg_conc_lin` over `sample_collect_date`.

4. **Summary metrics** — a row of `st.metric` cards at the top showing:
   total samples, detection rate (%), date range covered.

## Rules

- One file: `app.py`. No imports beyond the standard library, pandas, plotly,
  and streamlit.
- Short comments explaining *why* (not *what*) for any non-obvious step.
- Derive all filter options from the data — never hardcode states or dates.
- Sidebar controls must actually filter the data shown in every chart.

After writing the file, tell me how to start the app and what the three main
sections look like. If a design choice is ambiguous, make a sensible default
and note it.
