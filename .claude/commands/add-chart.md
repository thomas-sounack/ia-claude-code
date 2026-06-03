---
description: Add a new chart (and its control) to the dashboard
argument-hint: <describe the chart you want>
---

Add a new visualization to `app.py`: **$ARGUMENTS**

Follow the project conventions in `CLAUDE.md`:

- Use **Plotly** for the figure and render it with `st.plotly_chart(...)`.
- If the chart needs the user to choose something (a state, a date range, a
  metric), add the matching **Streamlit control in the sidebar** and wire it up.
- Reuse the existing cached data-loading function — don't re-read the CSVs.
- Keep everything in `app.py`. Add a short comment explaining what the chart
  shows and why.
- Respect the data gotchas: the `-1`/blank sentinels are already cleaned to NaN
  in the loader, and dates are parsed — use the cleaned columns.

After adding it, tell me where it appears in the layout and remind me that
Streamlit hot-reloads, so I can just save and look at the browser. If anything
about the request is ambiguous, make a sensible choice and note it rather than
stopping to ask.
