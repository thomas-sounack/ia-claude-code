# Installing Claude Code (managed settings) — instructions to hand out

Give this to the person doing the install. It covers macOS, Linux, and Windows.

---

## Before you hand this to anyone

**1. `managed_claude_code/` is not committed.** Commit and push it, or no URL-based
install can resolve.

**2. The repo is private.** Unauthenticated requests to `raw.githubusercontent.com`
return **404** for every path in this repo — including the root `install.sh` that
the top-level README already documents. So the `curl … | bash` one-liners do not
work for end users today.

Either make the repo public, or skip URLs and hand people the script file directly
(Teams, email, network share). **Every section below leads with a file-based path
that works either way.**

---

## First: is the person a local admin?

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

Policy lands in `/Library/Application Support/ClaudeCode/`

1. Open **Terminal** (Applications → Utilities, or ⌘-Space → "Terminal").

2. Run the installer. Note there is **no `sudo`** in front of it:

   ```bash
   bash managed_claude_code/install.sh
   ```

   Or, once the repo is public and pushed:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/managed_claude_code/install.sh | bash
   ```

3. **Enter your Mac password** when prompted. This happens early, right after the
   banner — that's expected, not a problem.

4. If a dialog offers to install **Xcode Command Line Tools**, click Install, wait
   for it to finish, then press Enter in the Terminal. (Only appears if Git is
   missing.)

5. A **browser window opens for Databricks**. Log in with your DFCI account.

6. Open a **new** Terminal window, then run `claude`. A new window is required so
   the updated PATH takes effect.

> ⚠️ **Do not run it with `sudo`.** Steps 1–6 of the script install tooling into
> *your* home directory and create *your* Databricks login. Under `sudo` those land
> in root's home and authentication silently breaks. The script detects this and
> refuses to run — that refusal is working as intended.

---

## Linux / WSL

Policy lands in `/etc/claude-code/`

Unlike macOS, the script will **not** install missing prerequisites — it checks and
exits. Make sure these are present first:

- `git`, `python3`, `unzip`, `curl`
- The user must be in `sudoers`

1. Install anything missing, e.g. on Debian/Ubuntu:

   ```bash
   sudo apt-get update && sudo apt-get install -y git python3 unzip curl
   ```

2. Run the installer — again, **no `sudo`**:

   ```bash
   bash managed_claude_code/install.sh
   ```

3. Enter your password when prompted, then complete the **Databricks browser
   login**. On a headless box the Databricks CLI prints a URL to open elsewhere.

4. Open a new shell, then run `claude`.

---

## Windows

Policy lands in `C:\Program Files\ClaudeCode\`

> ⚠️ **Read this first.** The whole script runs as the elevated account. If the
> account you elevate with is **not** the account you work in every day, the
> Databricks login and all the tooling land in the *admin's* profile, and your
> normal account gets a policy it cannot use.
>
> **Only proceed if you are a local administrator of your own account** — i.e. a UAC
> prompt appears and you approve it, rather than typing a different username.
> Otherwise use `no_code_claude_code/`, or have IT deploy the policy centrally.

1. **Save `install.ps1`** somewhere simple, such as your Downloads folder.

   A file is more reliable than a URL here: the repo is private, and the clone route
   needs Git — which is what the script installs.

2. Press **Start**, type `PowerShell`, **right-click** Windows PowerShell and choose
   **Run as administrator**. Approve the UAC prompt.

3. Change to the folder holding the file, then run it:

   ```powershell
   cd "$env:USERPROFILE\Downloads"
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

   `-ExecutionPolicy Bypass` applies to this one run only. Never run
   `Set-ExecutionPolicy` — it fails outright on Group-Policy-managed machines.

4. A **browser window opens for Databricks**. Log in with your DFCI account.

5. Open a **new** PowerShell window (normal, not elevated), then run `claude`.

`ERROR: Administrator rights are required` means the window isn't elevated. Close it
and repeat step 2 — right-click is required; opening PowerShell normally won't do.

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
| Authentication fails when Claude Code starts | The Databricks profile is missing or expired. Re-run:<br>`databricks auth login --host https://adb-2613326130799470.10.azuredatabricks.net --profile claude_code_workspace` |
| `claude: command not found` | The terminal predates the PATH change. Open a new window. |
| Web search or fetch is blocked | Expected. `WebFetch` and `WebSearch` are denied by policy so web access flows through the governed `DFCI-web-mcp` proxy instead. Subagents inherit this too. |
| Artifacts / `/login` don't work | Expected. `apiKeyHelper` takes precedence over a claude.ai account login. |

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
