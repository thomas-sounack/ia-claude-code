# Claude Code — enterprise managed settings installer

This installer configures Claude Code the same way `no_code_claude_code/` does,
but deploys the configuration as **enterprise managed settings** instead of
user-scope settings.

## Why this variant exists

The other two installers write `~/.claude/settings.json`. That file is advisory —
any user can edit it to repoint `ANTHROPIC_BASE_URL` away from the DFCI AI
gateway, drop the `WebFetch`/`WebSearch` deny rules, or swap in different model
IDs.

Managed settings sit at the **top of Claude Code's precedence chain**. Nothing
below them can override: not `~/.claude/settings.json`, not a project's
`.claude/settings.json`, not `.claude/settings.local.json`, not even the
`--settings` CLI flag.

## Comparison

| | root `install.sh` | `no_code_claude_code/` | `managed_claude_code/` |
|---|---|---|---|
| Clones the sample repo | yes | no | no |
| Config scope | project | user | **enterprise managed** |
| User can override | yes | yes | **no** |
| Needs admin rights | no | no | **yes** |
| Writes `~/.claude/settings.json` | no | yes | no |
| Writes `~/.mcp.json` | yes | yes | no |

## Usage

> For step-by-step instructions to hand to the person doing the install, see
> [INSTALL-INSTRUCTIONS.md](INSTALL-INSTRUCTIONS.md). This section is the reference
> summary.

**macOS / Linux** — run as yourself, *not* with `sudo`. The script prompts for
your password when it needs administrator rights:

```bash
curl -fsSL https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/managed_claude_code/install.sh | bash
```

or, from a clone:

```bash
bash managed_claude_code/install.sh
```

> Do **not** run `sudo bash install.sh`. Steps 1–6 install tooling into your home
> directory and step 3 opens a browser to create your Databricks OAuth profile.
> Under `sudo` those all land in root's home, and the token helper then finds no
> credentials to read. The script detects this and refuses to run.

**Windows** — must be run from an **elevated** PowerShell (Start → type
"PowerShell" → right-click → Run as administrator):

```powershell
irm https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/managed_claude_code/install.ps1 | iex
```

or, from a clone:

```powershell
powershell -ExecutionPolicy Bypass -File managed_claude_code\install.ps1
```

The script refuses to run unelevated rather than self-elevating. See
[the Windows caveat](#windows-caveat-split-admin-accounts) below.

> Because `irm … | iex` runs in the caller's scope, every error path in
> `install.ps1` bails out with `return`, not `exit` — `exit` would terminate the
> whole PowerShell session and close the window before the user could read the
> error. Don't "fix" those back to `exit`.

## What gets installed

| Platform | Managed config directory |
|---|---|
| macOS | `/Library/Application Support/ClaudeCode/` |
| Linux / WSL | `/etc/claude-code/` |
| Windows | `C:\Program Files\ClaudeCode\` |

> ⚠️ Not `C:\ProgramData\ClaudeCode\`. That legacy Windows path stopped being
> read in Claude Code v2.1.75 — guides that still name it are out of date.

Three files land there, root/Administrator-owned:

- **`managed-settings.json`** — model IDs, `ANTHROPIC_BASE_URL`, custom headers,
  the `Bash(*)` allow rule, the `WebFetch`/`WebSearch` deny rules, and
  `apiKeyHelper`. Same schema as `settings.json`.
- **`managed-mcp.json`** — the `DFCI-web-mcp` server definition. Same format as a
  project `.mcp.json`.
- **`databricks-token-helper.sh`** (or `.ps1` + `.cmd` on Windows) — mode `0755`,
  root-owned. It is machine-wide because managed settings are machine-wide, but it
  shells out to `databricks auth token`, which reads the **invoking** user's
  `~/.databrickscfg` — so one shared script still gives every user their own
  credentials.

One piece stays per-user: `~/.claude.json` (`hasCompletedOnboarding`) is
global-config scope and cannot be managed.

### Side effects worth knowing

- **`WebFetch` and `WebSearch` become unoverridable.** That is the intent — web
  access is meant to flow through the governed `DFCI-web-mcp` proxy, whose
  `mcp__*` tools are unaffected. Note that subagents inherit the deny too, so a
  subagent asked to research something on the web will be blocked.
- **Deploying `managed-mcp.json` takes exclusive control of MCP.** Users can no
  longer add their own servers, `--mcp-config` is rejected, and claude.ai
  connectors are suppressed.
- Managed `env` sets what each session *starts* with. Users can still `/model`
  switch between the configured models.

## Verifying it took effect

```
claude            # then, inside Claude Code:
/status           # setting sources should include: Enterprise managed settings (file)
claude doctor     # reports any settings entries dropped as invalid
claude mcp list   # should list DFCI-web-mcp only
```

The strongest check is a negative test — put
`{"env":{"ANTHROPIC_BASE_URL":"https://example.invalid"}}` in
`~/.claude/settings.json`, start Claude Code, and confirm the managed base URL
still wins. Remove it afterwards.

### If `/status` does not show the managed source

Sources **within** the managed tier do not merge — the highest-precedence one
wins outright, and the rest are ignored silently. Ranked highest first:

1. Server-managed settings from the claude.ai admin console
2. MDM / OS policies — macOS `com.anthropic.claudecode` configuration profile,
   Windows `HKLM\SOFTWARE\Policies\ClaudeCode`
3. The `managed-settings.json` file *(what this installer writes)*
4. Windows `HKCU` registry

So if DFCI IT already pushes a Jamf profile or an Intune/GPO registry policy, our
file is ignored entirely. Both installers check for this and print a warning, but
they still write the file — staging it may be intentional.

## Windows caveat: split-admin accounts

Because the script requires an elevated shell and does not self-elevate, the
whole run — including the per-user steps — executes as the elevated account.

- **If you are a local admin** (UAC elevation of your own account): fine. Same
  profile, everything lands where you expect.
- **If admin is a separate account**: steps 2–5 install into the *admin's*
  `%USERPROFILE%`, and step 3's `databricks auth login` writes the *admin's*
  OAuth profile. Your everyday account gets the machine-wide policy but no
  tooling and no credentials.

For split-admin fleets, deploy the two JSON files and the token helper via
Intune/GPO, then have each user run `no_code_claude_code/install.ps1`
unelevated for the per-user pieces.

Self-relaunching with `Start-Process -Verb RunAs` was considered and rejected:
the script is delivered via `irm … | iex`, so there is no file on disk to
re-launch, and re-downloading inside an elevated child would put *everything* in
the admin's profile — the same problem, just hidden.

## Rollback

Removing the directory removes the policy. Claude Code falls back to whatever
user/project settings exist.

**macOS**
```bash
sudo rm -rf "/Library/Application Support/ClaudeCode"
```

**Linux**
```bash
sudo rm -rf /etc/claude-code
```

**Windows** (elevated)
```powershell
Remove-Item -Recurse -Force "$env:ProgramFiles\ClaudeCode"
```

Note that rollback does **not** restore a `~/.claude/settings.json` — this
installer never wrote one. After rollback, users have no DFCI configuration at
all until `no_code_claude_code/install.sh` is run.

Re-running the installer backs up any existing `managed-settings.json` and
`managed-mcp.json` to `*.json.bak` first, so a re-run is recoverable.
