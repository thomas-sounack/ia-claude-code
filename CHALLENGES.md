# Challenges — pick ONE (15 minutes)

You've built the dashboard together. Now make it your own. **Pick one** of the
three challenges below and work on it solo. Presenters are circulating — wave
one of us over if you get stuck. We'll share a few results at the end.

There's no single "right" answer. The point is to drive Claude Code yourself.

---

## Challenge A — Add filters

**Goal:** Make the dashboard more interactive by adding filters for **year** and
**pathogen/category**.

Try a prompt like:

> Add a sidebar control to filter the data by year (derived from
> `sample_collect_date`), and another to pick which pathogen(s) to show. Update
> the charts to respect both filters.

Stretch: add a "detections only" toggle that filters to rows where
`pcr_target_detect` is `yes`.

This is a great choice if you want more practice **iterating on a real app** with
Claude Code.

---

## Challenge B — Write a CLAUDE.md for your own project

**Goal:** Take the `CLAUDE.md` skill home. Open one of your **own** real projects
(or a folder you work in) in a new terminal and have Claude Code help you draft a
`CLAUDE.md` for it.

Try:

> Look around this project and draft a CLAUDE.md: a short overview, how to run
> it, where the important code lives, and the conventions you should follow. Ask
> me anything you can't infer.

This is the **always-works** challenge — it needs no dataset and no app. If
you're newer to coding, start here: it's the single most useful artifact you can
walk away with.

---

## Challenge C — Two agents in parallel

**Goal:** Use **subagents** to do two analyses at once.

This repo ships a `dataset-analyst` subagent (see `.claude/agents/`). Open **two
terminals** in this folder and, in each, ask Claude Code to use the
`dataset-analyst` subagent for a different question — for example:

- Terminal 1: "Use the dataset-analyst subagent to find the 5 states with the
  highest measles detection rate."
- Terminal 2: "Use the dataset-analyst subagent to find how avian H5 detections
  changed over time, by month."

Watch them work independently. Stretch: define a **second** agent (e.g. a
`chart-builder`) in `.claude/agents/` and give it a different role.

This is the **depth** challenge — best if you finished the build early and want
to see where agentic workflows go.
