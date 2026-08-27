# Claude Code Setup — DFCI

This repo contains everything you need to set up **Claude Code** with DFCI's Databricks integration: an automated installer, project configuration, and a sample Streamlit dashboard project to get started with.

---

## Setup

Run the installer for your OS — it handles everything (Git, Databricks CLI, Claude Code, uv, repo clone):

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/install.sh | bash
```

**Windows (PowerShell)**
```powershell
irm https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/install.ps1 | iex
```

Once done, start Claude Code with:

**macOS / Linux**
```bash
cd ~/ia-claude-code && claude
```

**Windows (PowerShell)**
```powershell
cd "$env:USERPROFILE\ia-claude-code"; claude
```

---

## What's in here

| Path | What it is |
|------|------------|
| `cdc_data/` | Two CDC wastewater CSV datasets for the sample project |
| `CLAUDE.md` | Project briefing — tells Claude about the codebase and conventions |
| `.claude/commands/` | Custom slash commands (e.g. `/explore-data`, `/fetch-dictionary`) |
| `.claude/agents/` | Example subagent definition |
| `CHALLENGES.md` | Optional practice challenges |
| `REFERENCE.md` | Key commands and patterns |
| `no_code_claude_code/` | Standalone installer for environments without a code editor |
| `managed_claude_code/` | Installer that deploys the config as enterprise managed settings (requires admin) |

---

## Sample project

The repo includes a **local data visualization dashboard** built with Streamlit and Plotly, using two real CDC wastewater surveillance datasets (Avian Influenza A H5 and Measles). It's a good starting point for exploring Claude Code features — open it, ask Claude to add a chart, or use it as a template for your own project.

```bash
uv venv
source .venv/bin/activate   # macOS / Linux
# .venv\Scripts\activate    # Windows
uv pip install -r requirements.txt
uv run streamlit run app.py
```
