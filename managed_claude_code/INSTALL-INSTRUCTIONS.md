# Installing Claude Code (managed settings)

Instructions to hand to the person doing the install. One command per platform.

---

## First: are they a local admin?

This installer writes a policy file into a protected system directory, which needs
administrator rights. If they don't have them, *this is the wrong installer* — send
them elsewhere rather than letting them fail halfway through.

| Situation | What to give them |
|---|---|
| Has admin rights on their own machine | **This document.** Config is enforced and can't be edited away. |
| No admin rights | `no_code_claude_code/` instead — same settings, user scope, no elevation. They can override it, but it works. |
| Windows, admin is a *separate* account | Do not use this installer. See the Windows warning below. |
| Fleet-wide rollout | Ship the policy files via Jamf / Intune / GPO, then have each user run `no_code_claude_code/` unelevated for the per-user pieces. |

---

## macOS

Open **Terminal** (⌘-Space, type "Terminal"), then run:

```bash
curl -fsSL https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/managed_claude_code/install.sh | bash
```

Note there is **no `sudo`** in front of it. What to expect:

1. **A password prompt, early on** — right after the banner. That's expected; the
   script needs it to write the machine-wide policy.
2. **Possibly an Xcode Command Line Tools dialog** — click Install, wait for it to
   finish, then press Enter in the Terminal. Only appears if Git is missing.
3. **A browser window for Databricks** — log in with your DFCI account.

When it finishes, open a **new** Terminal window (so the updated PATH takes effect)
and run:

```bash
claude
```

> ⚠️ **Do not run it with `sudo`.** The script installs tooling into *your* home
> directory and creates *your* Databricks login. Under `sudo` those land in root's
> home and authentication silently breaks. The script detects this and refuses to
> run — that refusal is working as intended.

Policy lands in `/Library/Application Support/ClaudeCode/`.

---

## Linux / WSL

Unlike macOS, the script will **not** install missing prerequisites — it checks and
exits. Install them first if needed:

```bash
sudo apt-get update && sudo apt-get install -y git python3 unzip curl
```

Then run the installer — again, **no `sudo`**:

```bash
curl -fsSL https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/managed_claude_code/install.sh | bash
```

Enter your password when prompted, then complete the **Databricks browser login**.
On a headless box the Databricks CLI prints a URL to open on another machine.

When it finishes, open a new shell and run `claude`.

Policy lands in `/etc/claude-code/`.

---

## Windows

> ⚠️ **Read this before starting.** The whole script runs as the elevated account.
> If the account you elevate with is **not** the account you work in every day, the
> Databricks login and all the tooling land in the *admin's* profile, and your normal
> account gets a policy it cannot use.
>
> **Only proceed if you are a local administrator of your own account** — i.e. a UAC
> prompt appears and you approve it, rather than typing a different username.
> Otherwise use `no_code_claude_code/`, or have IT deploy the policy centrally.

**Step 1 — open an elevated PowerShell.** Press **Start**, type `PowerShell`,
**right-click** Windows PowerShell, choose **Run as administrator**, and approve the
UAC prompt. This is required: the script refuses to run unelevated rather than
silently putting things in the wrong place.

**Step 2 — run this one command:**

```powershell
irm https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/managed_claude_code/install.ps1 | iex
```

A **browser window opens for Databricks** — log in with your DFCI account.

When it finishes, open a **new** PowerShell window (normal, not elevated) and run:

```powershell
claude
```

If you see `ERROR: Administrator rights are required`, the window wasn't elevated.
Repeat step 1 — right-click is required; opening PowerShell normally won't do.

Policy lands in `C:\Program Files\ClaudeCode\`.

---

## Confirm it worked

Start Claude Code with `claude`, then run these three checks. All three apply on
every platform.

| Check | Expected |
|---|---|
| `/status` | Setting sources include **Enterprise managed settings (file)**. This is the one that matters. |
| `claude doctor` | Reports any settings entries dropped as invalid. Expect none. |
| `claude mcp list` | Lists **DFCI-web-mcp** and nothing else. |

**The real proof:** put `{"env":{"ANTHROPIC_BASE_URL":"https://example.invalid"}}`
into `~/.claude/settings.json`, start Claude Code, and confirm the DFCI gateway URL
still wins. Delete the file afterwards.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `/status` doesn't list the managed source | A higher-precedence managed source is winning. Managed sources **do not merge** — highest wins outright, ranked: admin-console settings, then MDM/GPO policy, then this file. If IT already pushes a Jamf profile or `HKLM\SOFTWARE\Policies\ClaudeCode`, this file is ignored. The installers warn when they detect it. |
| `ERROR: do not run this script with sudo` | Working as designed. Re-run without `sudo`; the script elevates on its own. |
| `ERROR: sudo is not available` | The account can't elevate. Use `no_code_claude_code/`, or ask IT to deploy the policy. |
| `ERROR: Administrator rights are required` (Windows) | The PowerShell window isn't elevated. Right-click → Run as administrator. |
| Authentication fails when Claude Code starts | The Databricks profile is missing or expired. Re-run:<br>`databricks auth login --host https://adb-2613326130799470.10.azuredatabricks.net --profile claude_code_workspace` |
| `claude: command not found` | The terminal predates the PATH change. Open a new window. |
| Web search or fetch is blocked | Expected. `WebFetch` and `WebSearch` are denied by policy so web access flows through the governed `DFCI-web-mcp` proxy instead. Subagents inherit this too. |
| Artifacts or `/login` don't work | Expected. `apiKeyHelper` takes precedence over a claude.ai account login. |

---

## Removing it

Deleting the directory removes the policy. Claude Code then falls back to whatever
user or project settings exist — and since this installer never writes a
`~/.claude/settings.json`, that may be nothing at all.

```bash
sudo rm -rf "/Library/Application Support/ClaudeCode"   # macOS
sudo rm -rf /etc/claude-code                            # Linux
```

```powershell
Remove-Item -Recurse -Force "$env:ProgramFiles\ClaudeCode"   # Windows, elevated
```

Re-running an installer backs up any existing `managed-settings.json` and
`managed-mcp.json` to `*.json.bak` first, so a re-run is recoverable.
