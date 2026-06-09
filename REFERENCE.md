# Claude Code — Reference Card

Session takeaway

---

## Everyday commands

| Command | What it does | 
|---------|--------------|
| `claude` | Start an interactive session in the current folder |
| `claude -p "..."` | **Headless mode** — run one prompt, print the answer, exit (great for scripts) |
| `/help` | List available commands |
| `/clear` | Clear the conversation and start fresh (do this between unrelated tasks) |
| `/init` | Have Claude generate a starter `CLAUDE.md` for the current project |
| `Esc` | Interrupt Claude mid-action |
| `/agents` | View and manage subagents |

### Headless mode example

```bash
claude -p "Which 5 states have the most measles detections? Use cdc_data/."
```

This is just a command - it can be piped, scheduled, droped into a Makefile.

---

## CLAUDE.md — the project briefing

Claude reads `CLAUDE.md` automatically on every session. A good one has:

- **Project overview** — what this is, in two sentences.
- **How to run** — the exact commands to install and start it.
- **The data / the code map** — where the important things live, and any gotchas.
- **Coding standards & constraints** — the rules you want followed (style, "keep
  it in one file", "no new dependencies", etc.).

Tip: start one with `/init`, then edit. Add a rule whenever you catch yourself
correcting Claude the same way twice.

---

## Custom slash commands

Drop a markdown file in `.claude/commands/`. The filename becomes the command.
This repo ships:

| Command | What it does |
|---------|--------------|
| `/fetch-dictionary` | Looks up the CDC field definitions online and writes them into `CLAUDE.md` |
| `/explore-data` | Profiles the datasets and surfaces data-quality issues |
| `/add-chart <description>` | Adds a Plotly chart + its control to the app |

A command is just a reusable prompt. `$ARGUMENTS` in the file becomes whatever
you type after the command.

---

## Subagents

Drop a markdown file in `.claude/agents/` to define a focused helper with its own
role and its own tool permissions. This repo ships `dataset-analyst` (read-only
data analysis). Run several in parallel terminals to do independent work at once.

---

## The three challenges (in case you want them later)

- **A** — Add year + pathogen filters to the dashboard.
- **B** — Write a `CLAUDE.md` for one of your own projects.
- **C** — Run two `dataset-analyst` agents in parallel on different questions.

See `CHALLENGES.md` for the full prompts.

---

## Where to go next

- Run `/init` in your own repo and commit the `CLAUDE.md`.
- Turn a repetitive prompt into a `.claude/commands/` file.
- Try `claude -p` inside a shell script for something you do by hand today.
