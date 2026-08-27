#!/usr/bin/env bash
set -euo pipefail

echo ''
echo '============================================'
echo '   Claude Code Setup'
echo '============================================'
echo ''

DATABRICKS_HOST="https://adb-2613326130799470.10.azuredatabricks.net"
DATABRICKS_PROFILE="claude_code_workspace"
DBR_CLI_VERSION="v1.1.0"

# ── Step 1: Git ──────────────────────────────────────────────────────────────
echo '============================================'
echo ' Step 1/9: Checking Git'
echo '============================================'
if ! git --version >/dev/null 2>&1; then
    OS="$(uname -s)"
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

    OS="$(uname -s)"
    ARCH="$(uname -m)"
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
                x86_64|amd64) SUFFIX="linux_amd64"  ;;
                aarch64|arm64) SUFFIX="linux_arm64" ;;
                *) echo "Unsupported Linux architecture: $ARCH"; exit 1 ;;
            esac
            ;;
        *)
            echo "Unsupported OS: $OS"; exit 1 ;;
    esac

    ZIP_NAME="databricks_cli_${DBR_CLI_VERSION#v}_${SUFFIX}.zip"
    ZIP_URL="https://github.com/databricks/cli/releases/download/${DBR_CLI_VERSION}/${ZIP_NAME}"

    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT
    echo "Downloading $ZIP_NAME..."
    curl -fsSL "$ZIP_URL" -o "$TMP_DIR/databricks-cli.zip"
    unzip -o "$TMP_DIR/databricks-cli.zip" databricks -d "$HOME/.local/bin" >/dev/null
    chmod +x "$HOME/.local/bin/databricks"
else
    echo 'Databricks CLI already installed -- skipping.'
fi

export PATH="$HOME/.local/bin:$PATH"

for RC_FILE in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC_FILE" ] && [ -w "$RC_FILE" ] && ! grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$RC_FILE"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC_FILE"
    fi
done

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
    OS="$(uname -s)"
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
fi
for RC_FILE in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc"; do
    touch "$RC_FILE" 2>/dev/null || true
    if [ -w "$RC_FILE" ] && ! grep -qF '.local/bin' "$RC_FILE"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC_FILE"
    fi
done
echo 'Claude Code CLI ready.'

# ── Step 6/9: uv ─────────────────────────────────────────────────────────────
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

# ── Step 7/9: Write Claude Code configuration ─────────────────────────────────
echo ''
echo '============================================'
echo ' Step 7/9: Writing Claude Code configuration'
echo '============================================'
mkdir -p "$HOME/.claude"

# Write .mcp.json so Claude Code connects to the Databricks MCP server
cat > "$HOME/.mcp.json" << 'MCP_EOF'
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

# Write global settings.json
python3 - "$HOME/.claude/settings.json" "$HOME" << 'PY'
import shlex
import sys, json, os

settings_path, home = sys.argv[1], sys.argv[2]
settings = {
    "_version": "1.0.0",
    "_mode": "permissive",
    "apiKeyHelper": shlex.quote(home + "/.claude/databricks-token-helper.sh"),
    "companyAnnouncements": ["Dana-Farber Cancer Institute"],
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
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
PY

echo 'Claude Code configuration written.'

# ── Step 8/9: Token helper ────────────────────────────────────────────────────
echo ''
echo '============================================'
echo ' Step 8/9: Writing token helper'
echo '============================================'
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/databricks-token-helper.sh" << 'HELPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${DATABRICKS_CONFIG_PROFILE:-claude_code_workspace}"
TOKEN_JSON="$(databricks auth token -p "$PROFILE" -o json)"
printf '%s' "$TOKEN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])'
HELPER_EOF
chmod 700 "$HOME/.claude/databricks-token-helper.sh"
echo "Token helper written to $HOME/.claude/databricks-token-helper.sh"

# ── Step 9/9: hasCompletedOnboarding ─────────────────────────────────────────
echo ''
echo '============================================'
echo ' Step 9/9: Configuring Claude Code'
echo '============================================'
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

echo ''
echo '============================================'
echo ' Installation complete!'
echo '============================================'
echo ''
echo 'Open a new terminal window, then run:'
echo '  claude'
echo ''
echo '(A new terminal is needed so PATH changes take effect.)'
echo ''
