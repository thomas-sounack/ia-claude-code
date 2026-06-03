---
description: Look up the official CDC field definitions and write them into CLAUDE.md
---

The two datasets in `cdc_data/` come from the CDC's public data portal. Each
dataset has a web page describing every column ("about this data"). Your job is
to **look up those official field definitions and record them in `CLAUDE.md`** so
the whole project has a shared data dictionary.

The dataset pages are:

- Measles: https://data.cdc.gov/Public-Health-Surveillance/CDC-Wastewater-Data-for-Measles/akvg-8vrb/about_data
- Avian Influenza A (H5): https://data.cdc.gov/Public-Health-Surveillance/CDC-Wastewater-Data-for-Avian-Influenza-A-H5-/mtpu-urpp/about_data

These are Socrata-hosted datasets. The human-facing `about_data` pages are
rendered with JavaScript, so fetching the HTML directly won't give you the field
descriptions. Instead, Socrata exposes the column metadata as JSON at:

- `https://data.cdc.gov/api/views/akvg-8vrb.json` (Measles)
- `https://data.cdc.gov/api/views/mtpu-urpp.json` (Avian H5)

Each JSON response has a `columns` array; every entry has a `fieldName` and a
`description`. Both datasets share the same schema, so you only need to read one
to build the dictionary — but feel free to confirm they match.

Steps:

1. Retrieve the column metadata (use `curl` to fetch the JSON, then parse it —
   `WebFetch` on the `about_data` page will only return page chrome).
2. Build a clean markdown table with two columns: **Field** and **Description**.
   Keep all 38 fields. Trim each description to its first sentence or two so the
   table stays readable.
3. Replace the placeholder comment under the **### Data dictionary** heading in
   `CLAUDE.md` with that table. Leave the rest of `CLAUDE.md` untouched.

When you're done, briefly tell me how many fields you documented and call out
any column whose meaning is important for visualizing the data (e.g. which one
is the detection flag, which one is the concentration value to plot).
