# CLAUDE.md

> This file is the "briefing" Claude Code reads automatically every time it
> starts in this folder. It's how you give Claude persistent context about your
> project — what you're building, how to run it, where the data lives, and the
> rules you want it to follow. Think of it as onboarding docs for your AI
> teammate. Everything below is loaded into Claude's context on every session.

---

## Project overview

We're building a **local data visualization dashboard** for CDC wastewater
surveillance data. It's a single-page web app, written in Python with
**Streamlit**, that lets a user explore two datasets:

- **Avian Influenza A (H5)** wastewater detections
- **Measles** wastewater detections

The audience is non-experts: a public-health analyst should be able to open it,
pick a pathogen and a state, and immediately see trends over time and which
areas are reporting detections.

This is a teaching project for a workshop. **Favor clarity over cleverness.**

---

## How to run

```bash
pip install -r requirements.txt
streamlit run app.py
```

Streamlit opens the app in the browser and hot-reloads on save.

---

## The data

Both datasets live in `cdc_data/` as CSV files:

- `cdc_data/CDC_Wastewater_Data_for_Avian_Influenza_A_(H5)_20260603.csv` (~103k rows)
- `cdc_data/CDC_Wastewater_Data_for_Measles_20260603.csv` (~45k rows)

**Both files share the exact same 38-column schema**, so they can be loaded and
processed with the same code. A `pathogen` label (`"Avian Influenza A (H5)"` /
`"Measles"`) should be added when loading so the two can be combined or compared.

### Known gotchas (these are real — handle them when loading)

1. **Numbers contain comma thousands-separators inside quotes**, e.g.
   `population_served` is `"13,000"` and `pcr_target_avg_conc_lin` is
   `"218,388.46154"`. Read these with pandas' `thousands=','` or they'll come in
   as strings. The CSV is quoted, so a standard CSV parser handles the quoting.
2. **`-1` and empty values are "not reported" sentinels**, not real measurements
   (common in `flow_rate`, `rec_eff_percent`, `rec_eff_spike_conc`). Convert
   them to `NaN` before doing math or plotting, or they'll skew everything.
3. **`sample_collect_date` is the date to plot on** (format `YYYY-MM-DD`).
   Parse it to a real datetime. Range is roughly Dec 2024 → May 2026.
4. **`state_territory`** holds 2-letter lowercase codes (`pa`, `wi`, `hi`, ...).
5. **`pcr_target_detect`** is `"yes"`/`"no"` — the detection flag, great for a
   "detection rate" metric.

### Useful columns at a glance

- Geography: `state_territory`, `county_fips`, `counties_served`, `population_served`
- Time: `sample_collect_date`
- Detection: `pcr_target_detect` (yes/no)
- Concentration: `pcr_target_avg_conc_lin` (linear scale; good default y-axis)

### Data dictionary

<!--
  PLACEHOLDER — we'll fill this in LIVE during the session.
  Run the /fetch-dictionary slash command and Claude will look up the official
  CDC field definitions from the dataset's web page and write them here.
  This is the "wow" moment: Claude reads the source to learn the schema for us.
-->

---

## Coding standards & constraints

- **One file.** Keep the whole app in `app.py`. No packages, no `src/` layout.
  This is a small teaching project — a reader should see everything in one place.
- **Cache the data loading** with `@st.cache_data` so the app stays snappy on
  reload (the CSVs are large-ish).
- **Comment for non-experts.** Assume the reader knows a little Python but not
  pandas or Streamlit. Short comments explaining *why*, not *what*.
- **Readable over clever.** Prefer obvious pandas/Streamlit idioms over compact
  tricks. No premature abstraction.
- **No database, no build step, no JavaScript.** Streamlit + Plotly only.
- **Don't hardcode** the list of states or date ranges — derive them from the
  data so the app keeps working if the CSVs are updated.
- When adding a chart, also add the Streamlit control (selectbox, slider, etc.)
  that drives it, in the sidebar.
