#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
#  Claude Code Setup -- ENTERPRISE MANAGED SETTINGS variant
# =============================================================================
#
#  Unlike no_code_claude_code/install.sh (which writes user-scope config into
#  ~/.claude/settings.json and ~/.mcp.json), this installer writes ENTERPRISE
#  MANAGED SETTINGS into a system directory. Managed settings sit at the top of
#  Claude Code's precedence chain: they cannot be overridden by
#  ~/.claude/settings.json, a project .claude/settings.json, .settings.local.json,
#  or even the --settings CLI flag.
#
#  Writing to a system directory requires administrator rights, so this script
#  asks for your password via sudo. IMPORTANT: do NOT run this whole script with
#  `sudo bash`. Steps 1-6 install per-user tooling into $HOME and step 3 opens a
#  browser to create your Databricks OAuth profile -- under sudo those would all
#  land in root's home directory, and the token helper would then find no
#  profile to read. This script runs as you and elevates only for steps 7-8.
#
#  Usage (macOS / Linux):
#      bash managed_claude_code/install.sh
# =============================================================================

echo ''
echo '============================================'
echo '   Claude Code Setup (managed settings)'
echo '============================================'
echo ''

DATABRICKS_HOST="https://adb-2613326130799470.10.azuredatabricks.net"
DATABRICKS_PROFILE="claude_code_workspace"
DBR_CLI_VERSION="v1.1.0"

# ── Preamble: platform, elevation, precedence ────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"

# Where Claude Code looks for file-based managed configuration. These paths are
# fixed by Claude Code -- they are not configurable.
case "$OS" in
    Darwin) SYS_DIR="/Library/Application Support/ClaudeCode" ;;
    Linux)  SYS_DIR="/etc/claude-code" ;;
    *)      echo "ERROR: unsupported OS: $OS"; exit 1 ;;
esac

# Single scratch directory for staged files. cleanup() also stops the sudo
# keep-alive started below, so both are torn down by one trap.
TMP_DIR="$(mktemp -d)"
SUDO_KEEPALIVE_PID=""
cleanup() {
    rm -rf "$TMP_DIR"
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Refuse to run under sudo. See the header comment: the per-user steps would
# write into root's home instead of yours.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    echo 'ERROR: do not run this script with sudo.'
    echo ''
    echo 'Steps 1-6 install tools into your home directory and authenticate you'
    echo 'with Databricks. Under sudo those would land in root'"'"'s home and the'
    echo 'token helper would not find your credentials.'
    echo ''
    echo 'Re-run as yourself -- the script will prompt for your password when it'
    echo 'needs administrator rights:'
    echo '    curl -fsSL https://raw.githubusercontent.com/thomas-sounack/ia-claude-code/main/managed_claude_code/install.sh | bash'
    exit 1
fi

# A genuine root shell (a container, for example) is fine: nothing to elevate.
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    echo 'Running as root -- machine-wide files will be written directly.'
else
    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: sudo is not available, and writing to $SYS_DIR requires"
        echo 'administrator rights. Re-run as root, or ask your administrator to'
        echo 'deploy the managed configuration for you.'
        exit 1
    fi
    SUDO="sudo"

    # Prime the sudo credential cache up front so the password prompt appears
    # here -- with an explanation -- rather than surprising the user six steps in.
    # This script is meant to be usable via `curl ... | bash`, in which case stdin
    # is the pipe, so read the password from the terminal instead.
    echo 'Administrator access is required to install the machine-wide policy'
    echo "into:  $SYS_DIR"
    echo 'You will be prompted for your password now.'
    echo ''
    if ! sudo -v < /dev/tty; then
        echo 'ERROR: could not obtain administrator rights. Aborting.'
        exit 1
    fi
    echo 'Administrator access granted.'

    # Keep the credential cache warm for the rest of the run. Steps 2-6 include
    # large downloads and a browser OAuth login, which can easily outlast sudo's
    # default timeout (5 minutes on macOS). If the cache lapsed, step 7 would
    # need a fresh password -- but by then stdin may be the `curl | bash` pipe,
    # so the prompt would have nowhere to read from and the install would fail
    # after the user had already authenticated. Refresh every 50s instead.
    ( while true; do sudo -n true 2>/dev/null || exit; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
fi

# Warn if a higher-precedence managed source is already in play. Sources within
# the managed tier do NOT merge -- the first non-empty one wins outright. An MDM
# profile outranks the file this script writes, so the file would be silently
# ignored. Warn, but do not abort: staging the file may still be intentional.
if [ "$OS" = "Darwin" ]; then
    MDM_PLIST="/Library/Managed Preferences/com.anthropic.claudecode.plist"
    MDM_PLIST_USER="/Library/Managed Preferences/$(id -un)/com.anthropic.claudecode.plist"
    if [ -f "$MDM_PLIST" ] || [ -f "$MDM_PLIST_USER" ]; then
        echo ''
        echo '*****************************************************************'
        echo ' WARNING: an MDM configuration profile for Claude Code is already'
        echo ' installed on this Mac. MDM profiles OUTRANK the managed settings'
        echo ' file this script writes, and managed sources do not merge -- the'
        echo ' highest-precedence source wins outright.'
        echo ''
        echo ' The file will still be written, but Claude Code will IGNORE it'
        echo ' while the MDM profile is present. Verify afterwards with /status.'
        echo '*****************************************************************'
        echo ''
    fi
fi

HELPER_PATH="$SYS_DIR/databricks-token-helper.sh"

echo ''
echo "Platform:            $OS ($ARCH)"
echo "Managed config dir:  $SYS_DIR"
echo ''

# ── Step 1: Git ──────────────────────────────────────────────────────────────
echo '============================================'
echo ' Step 1/9: Checking Git'
echo '============================================'
if ! git --version >/dev/null 2>&1; then
    if [ "$OS" = "Darwin" ]; then
        echo 'Git not found -- installing Xcode Command Line Tools...'
        echo 'A dialog will appear asking you to install -- click Install and wait for it to complete.'
        xcode-select --install 2>/dev/null || true
        echo ''
        printf 'Press Enter once the Xcode Command Line Tools installation is complete: '
        read -r _ </dev/tty
        if ! git --version >/dev/null 2>&1; then
            echo 'ERROR: git still not found after installation. Please re-run this script.'
            exit 1
        fi
    else
        echo 'ERROR: git is not installed. Please install it and re-run.'
        exit 1
    fi
fi
echo "Git ready: $(git --version)"

# ── Step 2: Databricks CLI ───────────────────────────────────────────────────
echo ''
echo '============================================'
echo ' Step 2/9: Installing Databricks CLI'
echo '============================================'
if ! command -v databricks >/dev/null 2>&1; then
    echo 'Databricks CLI not found -- installing to ~/.local/bin...'
    mkdir -p "$HOME/.local/bin"

    case "$OS" in
        Darwin)
            case "$ARCH" in
                arm64)  SUFFIX="darwin_arm64"  ;;
                x86_64) SUFFIX="darwin_amd64"  ;;
                *) echo "Unsupported Mac architecture: $ARCH"; exit 1 ;;
            esac
            ;;
        Linux)
            case "$ARCH" in
                x86_64|amd64)  SUFFIX="linux_amd64" ;;
                aarch64|arm64) SUFFIX="linux_arm64" ;;
                *) echo "Unsupported Linux architecture: $ARCH"; exit 1 ;;
            esac
            ;;
    esac

    ZIP_NAME="databricks_cli_${DBR_CLI_VERSION#v}_${SUFFIX}.zip"
    ZIP_URL="https://github.com/databricks/cli/releases/download/${DBR_CLI_VERSION}/${ZIP_NAME}"

    echo "Downloading $ZIP_NAME..."
    curl -fsSL "$ZIP_URL" -o "$TMP_DIR/databricks-cli.zip"
    unzip -o "$TMP_DIR/databricks-cli.zip" databricks -d "$HOME/.local/bin" >/dev/null
    chmod +x "$HOME/.local/bin/databricks"
else
    echo 'Databricks CLI already installed -- skipping.'
fi

export PATH="$HOME/.local/bin:$PATH"
echo "Databricks CLI ready: $(databricks version)"

# ── Step 3: Databricks auth ──────────────────────────────────────────────────
echo ''
echo '============================================'
echo ' Step 3/9: Authenticating with Databricks'
echo '============================================'
echo 'A browser window will open -- log in with your DFCI account.'
databricks auth login --host "$DATABRICKS_HOST" --profile "$DATABRICKS_PROFILE"
echo 'Databricks authentication complete.'

# ── Step 4: Python ───────────────────────────────────────────────────────────
echo ''
echo '============================================'
echo ' Step 4/9: Checking Python'
echo '============================================'
if ! command -v python3 >/dev/null 2>&1; then
    echo 'ERROR: python3 is not installed.'
    if [ "$OS" = "Darwin" ]; then
        echo 'Install it with: xcode-select --install'
    else
        echo 'Install it via your package manager, then re-run.'
    fi
    exit 1
fi
echo "Python ready: $(python3 --version)"

# ── Step 5: Claude Code CLI ──────────────────────────────────────────────────
echo ''
echo '============================================'
echo ' Step 5/9: Installing Claude Code CLI'
echo '============================================'
if ! command -v claude >/dev/null 2>&1; then
    echo 'Claude Code not found -- downloading and installing...'
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
else
    echo 'Claude Code already installed -- skipping.'
fi
# Make ~/.local/bin permanent. Non-fatal: a read-only or absent rc file must not
# fail the install, since PATH is already exported for this session.
for RC_FILE in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc"; do
    touch "$RC_FILE" 2>/dev/null || true
    if [ -w "$RC_FILE" ] && ! grep -qF '.local/bin' "$RC_FILE"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC_FILE"
    fi
done
echo 'Claude Code CLI ready.'

# ── Step 6: uv ───────────────────────────────────────────────────────────────
echo ''
echo '============================================'
echo ' Step 6/9: Installing uv'
echo '============================================'
if ! command -v uv >/dev/null 2>&1; then
    echo 'uv not found -- installing...'
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
else
    echo 'uv already installed -- skipping.'
fi
echo "uv ready: $(uv --version)"

# ── Step 7: Managed configuration (requires root) ────────────────────────────
echo ''
echo '============================================'
echo ' Step 7/9: Writing managed configuration'
echo '============================================'

$SUDO mkdir -p "$SYS_DIR"
$SUDO chmod 755 "$SYS_DIR"

# Back up an existing policy so a re-run is recoverable.
if [ -f "$SYS_DIR/managed-settings.json" ]; then
    echo 'Existing managed-settings.json found -- backing it up to managed-settings.json.bak'
    $SUDO cp -p "$SYS_DIR/managed-settings.json" "$SYS_DIR/managed-settings.json.bak"
fi
if [ -f "$SYS_DIR/managed-mcp.json" ]; then
    echo 'Existing managed-mcp.json found -- backing it up to managed-mcp.json.bak'
    $SUDO cp -p "$SYS_DIR/managed-mcp.json" "$SYS_DIR/managed-mcp.json.bak"
fi

# Stage managed-settings.json as the current user, then install it as root.
# Generating via python3 means the JSON is well-formed by construction, and
# apiKeyHelper gets the absolute machine-wide helper path -- a ~-relative path
# would only be correct for whoever ran the installer.
#
# Claude Code runs apiKeyHelper's value as a raw `sh -c` command line, not an
# argv array, so the path must be shell-quoted here -- SYS_DIR is
# "/Library/Application Support/ClaudeCode" on macOS, and an unquoted space
# makes /bin/sh treat "/Library/Application" as the command.
python3 - "$TMP_DIR/managed-settings.json" "$HELPER_PATH" << 'PY'
import shlex
import sys, json

out_path, helper_path = sys.argv[1], sys.argv[2]
settings = {
    "companyAnnouncements": ["Dana-Farber Cancer Institute"],
    "apiKeyHelper": shlex.quote(helper_path),
    "permissions": {
        "allow": ["Bash(*)"],
        "deny": ["WebFetch", "WebSearch"]
    },
    "env": {
        "ANTHROPIC_MODEL": "custom_model_services.claude_code_sandbox.claude-sonnet-5",
        "ANTHROPIC_BASE_URL": "https://adb-2613326130799470.10.azuredatabricks.net/ai-gateway/anthropic",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "custom_model_services.claude_code_sandbox.claude-opus-5",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "custom_model_services.claude_code_sandbox.claude-sonnet-5",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "custom_model_services.claude_code_sandbox.claude-haiku-4-5",
        "ANTHROPIC_CUSTOM_HEADERS": "x-databricks-use-coding-agent-mode: true",
        "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
        "CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL": "1",
        "CLAUDE_CODE_SKIP_AUTH_LOGIN": "1"
    }
}
with open(out_path, "w") as f:
    json.dump(settings, f, indent=2)
PY

# managed-mcp.json uses the same format as a project .mcp.json file. Deploying it
# gives the managed tier exclusive control over MCP servers: users cannot add
# their own, and --mcp-config is rejected.
cat > "$TMP_DIR/managed-mcp.json" << 'MCP_EOF'
{
  "mcpServers": {
    "DFCI-web-mcp": {
      "type": "stdio",
      "command": "uvx",
      "args": [
        "uc-mcp-proxy",
        "--url",
        "https://mcp-web-2613326130799470.10.azure.databricksapps.com/mcp",
        "--auth-type",
        "databricks-cli",
        "--profile",
        "claude_code_workspace"
      ]
    }
  }
}
MCP_EOF

# `install -m` copies and sets the mode in one step; run as root so the files
# end up root-owned and world-readable (0644).
$SUDO install -m 644 "$TMP_DIR/managed-settings.json" "$SYS_DIR/managed-settings.json"
$SUDO install -m 644 "$TMP_DIR/managed-mcp.json"      "$SYS_DIR/managed-mcp.json"

echo "Managed configuration written to $SYS_DIR"

# ── Step 8: Machine-wide token helper (requires root) ────────────────────────
echo ''
echo '============================================'
echo ' Step 8/9: Writing machine-wide token helper'
echo '============================================'

# The helper is machine-wide because managed settings are machine-wide. It shells
# out to the Databricks CLI, which reads the *invoking* user's ~/.databrickscfg,
# so a single shared script still gives every user their own credentials.
#
# Mode 0755, not 0700: every user must be able to execute it. It must NOT be
# writable by non-root users -- it is referenced by a root-owned policy file, so
# a user-writable helper would be a privilege-escalation path.
cat > "$TMP_DIR/databricks-token-helper.sh" << 'HELPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${DATABRICKS_CONFIG_PROFILE:-claude_code_workspace}"
TOKEN_JSON="$(databricks auth token -p "$PROFILE" -o json)"
printf '%s' "$TOKEN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])'
HELPER_EOF

$SUDO install -m 755 "$TMP_DIR/databricks-token-helper.sh" "$HELPER_PATH"
echo "Token helper written to $HELPER_PATH"

# ── Step 9: hasCompletedOnboarding (per-user, unelevated) ─────────────────────
echo ''
echo '============================================'
echo ' Step 9/9: Configuring Claude Code'
echo '============================================'
# ~/.claude.json is global-config scope and cannot be managed, so this one piece
# stays per-user. Written unelevated, as the real user.
python3 << 'PY'
import json, os, tempfile

path = os.path.expanduser("~/.claude.json")
data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        data = {}
data["hasCompletedOnboarding"] = True
dir_ = os.path.dirname(os.path.abspath(path))
with tempfile.NamedTemporaryFile("w", dir=dir_, delete=False, suffix=".tmp") as tf:
    json.dump(data, tf, indent=2)
os.replace(tf.name, path)
PY
echo 'Claude Code configured.'

# ── Verification ─────────────────────────────────────────────────────────────
echo ''
echo '============================================'
echo ' Verifying'
echo '============================================'
if python3 -c "import json; json.load(open('$SYS_DIR/managed-settings.json'))" 2>/dev/null; then
    echo "OK: managed-settings.json is valid JSON"
else
    echo "ERROR: managed-settings.json did not parse as JSON!"
    exit 1
fi
if python3 -c "import json; json.load(open('$SYS_DIR/managed-mcp.json'))" 2>/dev/null; then
    echo "OK: managed-mcp.json is valid JSON"
else
    echo "ERROR: managed-mcp.json did not parse as JSON!"
    exit 1
fi
echo ''
ls -l "$SYS_DIR"

echo ''
echo '============================================'
echo ' Installation complete!'
echo '============================================'
echo ''
echo 'Open a new terminal window (so PATH changes take effect), then run:'
echo '  claude'
echo ''
echo 'To confirm the managed policy is actually in force:'
echo '  1. Inside Claude Code, run  /status'
echo '     -- the setting sources should include:'
echo '        Enterprise managed settings (file)'
echo '  2. Run  claude doctor'
echo '     -- reports any settings entries that were dropped as invalid.'
echo '  3. Run  claude mcp list'
echo '     -- should list DFCI-web-mcp only.'
echo ''
echo 'If /status does NOT show the managed source, a higher-precedence managed'
echo 'source is overriding it (an MDM profile, or server-managed settings from'
echo 'the admin console). Managed sources do not merge -- the highest wins.'
echo ''
