# Coding Assistants for Developers — Hands-on Lab

Welcome! In this 1-hour session you'll use **Claude Code** to build a local data
visualization website from scratch — no prior experience with the codebase
required. We'll be working with two real public-health datasets from the CDC.

By the end you'll have a working dashboard on your own machine, a reusable
`CLAUDE.md` template, and a reference card of the moves to try next.

---

## Before we start

You should already have:

1. **Claude Code installed and authenticated.** Test it by running `claude` in a
   terminal. If it opens, you're good.
2. **Python 3** installed. Test it with `python --version` (or `python3 --version`).

> Stuck on either? Flag a facilitator — grab a neighbor and pair up so we can
> keep moving.

---

## Get the starting point

```bash
git clone <REPO_URL_TBD>
cd ia-claude-code
claude
```

That's it — **don't build anything yet**. We'll do that together, live, using
Claude Code. The repo you just cloned has the datasets and the project setup,
but *no app code yet*. That's the point: we're going to write it together.

When you want to run the app (later in the session):

```bash
pip install -r requirements.txt
streamlit run app.py
```

---

## What's in here

| Path | What it is |
|------|------------|
| `cdc_data/` | The two CDC wastewater CSV datasets we'll visualize |
| `CLAUDE.md` | The project "briefing" we give Claude — we'll walk through it together |
| `.claude/commands/` | Custom slash commands (e.g. `/explore-data`, `/fetch-dictionary`) |
| `.claude/agents/` | An example subagent definition (used in Challenge C) |
| `CHALLENGES.md` | The three pick-one challenges for the second half |
| `REFERENCE.md` | Your takeaway card — key commands and patterns |
| `docs/` | Facilitator notes |

---

## Agenda (1 hour)

| Time | What we're doing |
|------|------------------|
| 0–5 min | Orientation & clone — get everyone to the same starting point |
| 5–13 min | `CLAUDE.md` walkthrough — how to teach Claude your project |
| 13–40 min | Guided build — build the dashboard together, layering in Claude Code features |
| 40–55 min | Challenge — pick one of three and build on your own (see `CHALLENGES.md`) |
| 55–60 min | Share-out & close |

Let's build something.
