$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# =============================================================================
#  Claude Code Setup -- ENTERPRISE MANAGED SETTINGS variant
# =============================================================================
#
#  Unlike no_code_claude_code\install.ps1 (which writes user-scope config into
#  %USERPROFILE%\.claude\settings.json and %USERPROFILE%\.mcp.json), this
#  installer writes ENTERPRISE MANAGED SETTINGS into C:\Program Files\ClaudeCode.
#  Managed settings sit at the top of Claude Code's precedence chain: they cannot
#  be overridden by user settings, project settings, or the --settings flag.
#
#  Writing to Program Files requires Administrator, so this script must be run
#  from an elevated PowerShell. It does NOT self-elevate -- see README.md for why,
#  and for the caveat that applies when your admin account differs from your
#  everyday account.
#
#  Usage (elevated PowerShell):
#      powershell -ExecutionPolicy Bypass -File managed_claude_code\install.ps1
# =============================================================================

$DatabricksHost    = 'https://adb-2613326130799470.10.azuredatabricks.net'
$DatabricksProfile = 'claude_code_workspace'
$DbrCliVersion     = 'v1.1.0'
$GitTag            = 'v2.54.0.windows.1'

# NOTE: error paths in this script bail out with `return`, never `exit`.
# This script is delivered via `irm ... | iex`, which runs in the caller's scope --
# there, `exit` terminates the whole PowerShell session, closing the window before
# the user can read the error message. `return` exits cleanly in both that mode and
# when the file is run with -File.

# Refresh PATH from registry so newly installed tools are available
function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

Write-Host ''
Write-Host '============================================'
Write-Host '   Claude Code Setup (managed settings)'
Write-Host '============================================'
Write-Host ''

# ── Preamble: elevation, target directory, precedence ────────────────────────

# $env:ProgramFiles rather than a hardcoded path, so this resolves correctly on
# localized Windows installs and where Program Files has been redirected.
$SysDir = Join-Path $env:ProgramFiles 'ClaudeCode'

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host 'ERROR: Administrator rights are required.' -ForegroundColor Red
    Write-Host ''
    Write-Host "This installer writes a machine-wide policy into:"
    Write-Host "    $SysDir"
    Write-Host 'which only an Administrator can write to.'
    Write-Host ''
    Write-Host 'To fix: press Start, type "PowerShell", right-click Windows PowerShell,'
    Write-Host 'choose "Run as administrator", then re-run this command.'
    Write-Host ''
    return
}
Write-Host 'Running elevated -- machine-wide policy can be written.'

# Warn if a higher-precedence managed source is already in play. Sources within
# the managed tier do NOT merge -- the first non-empty one wins outright. A Group
# Policy / Intune registry policy outranks the file this script writes, so the
# file would be silently ignored. Warn, but do not abort.
$PolicyKey = 'HKLM:\SOFTWARE\Policies\ClaudeCode'
if (Test-Path $PolicyKey) {
    $PolicyVal = (Get-ItemProperty -Path $PolicyKey -ErrorAction SilentlyContinue).Settings
    if ($PolicyVal) {
        Write-Host ''
        Write-Host '*****************************************************************' -ForegroundColor Yellow
        Write-Host ' WARNING: a Group Policy / Intune registry policy for Claude Code' -ForegroundColor Yellow
        Write-Host ' is already present at HKLM\SOFTWARE\Policies\ClaudeCode. Registry' -ForegroundColor Yellow
        Write-Host ' policies OUTRANK the managed settings file this script writes,'   -ForegroundColor Yellow
        Write-Host ' and managed sources do not merge -- the highest one wins.'        -ForegroundColor Yellow
        Write-Host ''                                                                  -ForegroundColor Yellow
        Write-Host ' The file will still be written, but Claude Code will IGNORE it'   -ForegroundColor Yellow
        Write-Host ' while that policy exists. Verify afterwards with /status.'        -ForegroundColor Yellow
        Write-Host '*****************************************************************' -ForegroundColor Yellow
        Write-Host ''
    }
}

$Ps1HelperPath = Join-Path $SysDir 'databricks-token-helper.ps1'
$CmdHelperPath = Join-Path $SysDir 'databricks-token-helper.cmd'

Write-Host ''
Write-Host "Managed config dir:  $SysDir"
Write-Host ''

# ── Step 1: Git ──────────────────────────────────────────────────────────────
Write-Host '============================================'
Write-Host ' Step 1/9: Checking Git'
Write-Host '============================================'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'Git not found -- installing Git for Windows...'
    $GitVersion = $GitTag.TrimStart('v') -replace '\.windows\.\d+$', ''
    $GitExeName = "Git-${GitVersion}-64-bit.exe"
    $GitUrl     = "https://github.com/git-for-windows/git/releases/download/${GitTag}/${GitExeName}"
    $GitTmpDir  = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $GitTmpDir | Out-Null
    $GitInstaller = Join-Path $GitTmpDir $GitExeName

    Write-Host "Downloading $GitExeName..."
    Invoke-WebRequest -Uri $GitUrl -OutFile $GitInstaller -UseBasicParsing
    Write-Host 'Installing Git (current user)...'
    Start-Process -FilePath $GitInstaller -ArgumentList '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/CURRENTUSER' -Wait
    Remove-Item -Path $GitTmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Update-Path
} else {
    Write-Host 'Git already installed -- skipping.'
}
Write-Host "Git ready: $(git --version)"

# ── Step 2: Databricks CLI ───────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 2/9: Installing Databricks CLI'
Write-Host '============================================'

if (-not (Get-Command databricks -ErrorAction SilentlyContinue)) {
    Write-Host 'Databricks CLI not found -- installing to ~/.local/bin...'
    $BinDir = Join-Path $env:USERPROFILE '.local\bin'
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

    $Arch    = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $Version = $DbrCliVersion.TrimStart('v')
    $ZipName = "databricks_cli_${Version}_windows_${Arch}.zip"
    $ZipUrl  = "https://github.com/databricks/cli/releases/download/${DbrCliVersion}/${ZipName}"

    $TmpDir = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $TmpDir | Out-Null
    try {
        Write-Host "Downloading $ZipName..."
        Invoke-WebRequest -Uri $ZipUrl -OutFile (Join-Path $TmpDir $ZipName) -UseBasicParsing
        Expand-Archive -Path (Join-Path $TmpDir $ZipName) -DestinationPath $TmpDir -Force
        Copy-Item -Path (Join-Path $TmpDir 'databricks.exe') -Destination (Join-Path $BinDir 'databricks.exe') -Force
    } finally {
        Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $UserPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if ($UserPath -notlike "*$BinDir*") {
        [System.Environment]::SetEnvironmentVariable('Path', "$UserPath;$BinDir", 'User')
    }
    $env:Path += ";$BinDir"
} else {
    Write-Host 'Databricks CLI already installed -- skipping.'
}
Write-Host "Databricks CLI ready: $(databricks version)"

# ── Step 3: Databricks auth ──────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 3/9: Authenticating with Databricks'
Write-Host '============================================'
Write-Host 'A browser window will open -- log in with your DFCI account.'
databricks auth login --host $DatabricksHost --profile $DatabricksProfile
Write-Host 'Databricks authentication complete.'

# ── Step 4: Python ───────────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 4/9: Checking Python'
Write-Host '============================================'

# Always install to a known path so we can bypass the Windows Store stub entirely.
$PyDir = Join-Path $env:USERPROFILE '.local\python'
$PythonExe = Join-Path $PyDir 'python.exe'

if (-not (Test-Path $PythonExe)) {
    Write-Host 'Python not found -- installing embeddable package...'
    $PyVer = '3.12.9'
    $PyZip = "python-${PyVer}-embed-amd64.zip"
    $PyUrl = "https://www.python.org/ftp/python/${PyVer}/${PyZip}"

    $TmpDir = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $TmpDir | Out-Null
    try {
        Write-Host "Downloading $PyZip..."
        Invoke-WebRequest -Uri $PyUrl -OutFile (Join-Path $TmpDir $PyZip) -UseBasicParsing
        Expand-Archive -Path (Join-Path $TmpDir $PyZip) -DestinationPath $PyDir -Force
    } finally {
        Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'Python already installed -- skipping.'
}

$UserPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
if ($UserPath -notlike "*$PyDir*") {
    [System.Environment]::SetEnvironmentVariable('Path', "$PyDir;$UserPath", 'User')
}
$env:Path = "$PyDir;$env:Path"
Write-Host "Python ready: $(& $PythonExe --version 2>&1)"

# ── Step 5: Claude Code CLI ──────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 5/9: Installing Claude Code CLI'
Write-Host '============================================'

# Claude Code needs bash.exe. Git for Windows doesn't add bash to PATH, only git.exe.
# Derive bash location from git.exe: git lives in <root>\cmd\git.exe or <root>\bin\git.exe,
# bash lives at <root>\usr\bin\bash.exe.
if (-not $env:CLAUDE_CODE_GIT_BASH_PATH) {
    $GitExe = Get-Command git -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    Write-Host "git.exe found at: $GitExe"
    if ($GitExe) {
        $GitRoot = Split-Path (Split-Path $GitExe -Parent) -Parent
        $BashCandidate = Join-Path $GitRoot 'usr\bin\bash.exe'
        Write-Host "Looking for bash at: $BashCandidate"
        if (Test-Path $BashCandidate) {
            $env:CLAUDE_CODE_GIT_BASH_PATH = $BashCandidate
            Write-Host "Using bash at: $BashCandidate"
        }
    }
    # Fallback: MinGit installed by this script
    if (-not $env:CLAUDE_CODE_GIT_BASH_PATH) {
        $MinGitBash = Join-Path $env:USERPROFILE '.local\mingit\usr\bin\bash.exe'
        if (Test-Path $MinGitBash) {
            $env:CLAUDE_CODE_GIT_BASH_PATH = $MinGitBash
            Write-Host "Using bash at: $MinGitBash"
        }
    }
}
if (-not $env:CLAUDE_CODE_GIT_BASH_PATH) {
    Write-Host 'ERROR: bash.exe not found. Please install Git for Windows from https://git-scm.com/downloads/win and re-run.' -ForegroundColor Red
    return
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host 'Claude Code not found -- downloading and installing...'
    Invoke-RestMethod -Uri 'https://claude.ai/install.ps1' | Invoke-Expression
    Update-Path
} else {
    Write-Host 'Claude Code already installed -- skipping.'
}

$ClaudeBin = Join-Path (Join-Path $env:USERPROFILE '.local') 'bin'
$UserPath  = [System.Environment]::GetEnvironmentVariable('Path', 'User')
if ((Test-Path $ClaudeBin) -and ($UserPath -notlike "*$ClaudeBin*")) {
    [System.Environment]::SetEnvironmentVariable('Path', "$UserPath;$ClaudeBin", 'User')
    $env:Path += ";$ClaudeBin"
}
Write-Host 'Claude Code CLI ready.'

# ── Step 6: uv ───────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 6/9: Installing uv'
Write-Host '============================================'

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host 'uv not found -- installing...'
    # Bypass the execution policy for this child process only. Never call
    # Set-ExecutionPolicy here -- it fails outright on Group-Policy-managed machines.
    powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"
    Update-Path
} else {
    Write-Host 'uv already installed -- skipping.'
}
Write-Host "uv ready: $(uv --version)"

# ── Step 7: Managed configuration (requires Administrator) ───────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 7/9: Writing managed configuration'
Write-Host '============================================'

# No ACL work needed: inheriting the Program Files ACLs already yields
# admin-writable / user-readable, which is exactly what we want.
New-Item -ItemType Directory -Force -Path $SysDir | Out-Null

$ManagedSettingsPath = Join-Path $SysDir 'managed-settings.json'
$ManagedMcpPath      = Join-Path $SysDir 'managed-mcp.json'

# Back up existing policy files so a re-run is recoverable.
if (Test-Path $ManagedSettingsPath) {
    Write-Host 'Existing managed-settings.json found -- backing it up to managed-settings.json.bak'
    Copy-Item -Path $ManagedSettingsPath -Destination "$ManagedSettingsPath.bak" -Force
}
if (Test-Path $ManagedMcpPath) {
    Write-Host 'Existing managed-mcp.json found -- backing it up to managed-mcp.json.bak'
    Copy-Item -Path $ManagedMcpPath -Destination "$ManagedMcpPath.bak" -Force
}

# apiKeyHelper points at the machine-wide helper's absolute path. A
# %USERPROFILE%-relative path would only be correct for whoever ran the installer.
#
# Claude Code runs apiKeyHelper's value as a raw command line (cmd.exe), not an
# argv array, so the path must be quoted here -- $env:ProgramFiles is normally
# "C:\Program Files", and an unquoted space would split the command in two.
$SettingsObj = [ordered]@{
    'companyAnnouncements' = @('Dana-Farber Cancer Institute')
    'apiKeyHelper'         = "`"$CmdHelperPath`""
    'permissions'          = [ordered]@{
        'allow' = @('Bash(*)')
        'deny'  = @('WebFetch', 'WebSearch')
    }
    'env'                  = [ordered]@{
        'ANTHROPIC_MODEL'                        = 'custom_model_services.claude_code_sandbox.claude-sonnet-5'
        'ANTHROPIC_BASE_URL'                     = 'https://adb-2613326130799470.10.azuredatabricks.net/ai-gateway/anthropic'
        'ANTHROPIC_DEFAULT_OPUS_MODEL'           = 'custom_model_services.claude_code_sandbox.claude-opus-5'
        'ANTHROPIC_DEFAULT_SONNET_MODEL'         = 'custom_model_services.claude_code_sandbox.claude-sonnet-5'
        'ANTHROPIC_DEFAULT_HAIKU_MODEL'          = 'custom_model_services.claude_code_sandbox.claude-haiku-4-5'
        'ANTHROPIC_CUSTOM_HEADERS'               = 'x-databricks-use-coding-agent-mode: true'
        'CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS' = '1'
        'CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL'      = '1'
        'CLAUDE_CODE_SKIP_AUTH_LOGIN'            = '1'
    }
}
[System.IO.File]::WriteAllText($ManagedSettingsPath, ($SettingsObj | ConvertTo-Json -Depth 20))

# managed-mcp.json uses the same format as a project .mcp.json file. Deploying it
# gives the managed tier exclusive control over MCP servers: users cannot add
# their own, and --mcp-config is rejected.
$McpJson = @'
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
'@
[System.IO.File]::WriteAllText($ManagedMcpPath, $McpJson)

Write-Host "Managed configuration written to $SysDir"

# ── Step 8: Machine-wide token helper (requires Administrator) ───────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 8/9: Writing machine-wide token helper'
Write-Host '============================================'

# The helper is machine-wide because managed settings are machine-wide. It shells
# out to the Databricks CLI, which reads the *invoking* user's .databrickscfg, so
# a single shared script still gives every user their own credentials.
#
# Note: $DbrProfile, not $Profile -- $Profile is a PowerShell automatic variable
# and shadowing it here would be a trap for anyone editing this later.
Set-Content -Path $Ps1HelperPath -Encoding UTF8 -Value @'
$ErrorActionPreference = "Stop"
$DbrProfile = if ($env:DATABRICKS_CONFIG_PROFILE) { $env:DATABRICKS_CONFIG_PROFILE } else { "claude_code_workspace" }
$TokenJson = databricks auth token -p $DbrProfile -o json
Write-Output ($TokenJson | ConvertFrom-Json).access_token
'@

# apiKeyHelper is invoked as a command, so it needs a .cmd entry point rather
# than a bare .ps1.
Set-Content -Path $CmdHelperPath -Encoding ASCII -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Ps1HelperPath`""

Write-Host "Token helper written to $CmdHelperPath"

# ── Step 9: hasCompletedOnboarding (per-user) ─────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 9/9: Configuring Claude Code'
Write-Host '============================================'
# .claude.json is global-config scope and cannot be managed, so this one piece
# stays per-user.
$ClaudeJsonPath = Join-Path $env:USERPROFILE '.claude.json'
if (Test-Path $ClaudeJsonPath) {
    try {
        $ClaudeData = Get-Content -Path $ClaudeJsonPath -Raw | ConvertFrom-Json
    } catch {
        $ClaudeData = [PSCustomObject]@{}
    }
} else {
    $ClaudeData = [PSCustomObject]@{}
}

if ($ClaudeData.PSObject.Properties['hasCompletedOnboarding']) {
    $ClaudeData.hasCompletedOnboarding = $true
} else {
    $ClaudeData | Add-Member -MemberType NoteProperty -Name 'hasCompletedOnboarding' -Value $true
}

[System.IO.File]::WriteAllText($ClaudeJsonPath, ($ClaudeData | ConvertTo-Json -Depth 20))
Write-Host 'Claude Code configured.'

# ── Verification ─────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Verifying'
Write-Host '============================================'
try {
    Get-Content -Path $ManagedSettingsPath -Raw | ConvertFrom-Json | Out-Null
    Write-Host 'OK: managed-settings.json is valid JSON'
} catch {
    Write-Host 'ERROR: managed-settings.json did not parse as JSON!' -ForegroundColor Red
    return
}
try {
    Get-Content -Path $ManagedMcpPath -Raw | ConvertFrom-Json | Out-Null
    Write-Host 'OK: managed-mcp.json is valid JSON'
} catch {
    Write-Host 'ERROR: managed-mcp.json did not parse as JSON!' -ForegroundColor Red
    return
}
Write-Host ''
Get-ChildItem $SysDir | Format-Table Mode, Length, LastWriteTime, Name

Write-Host ''
Write-Host '============================================'
Write-Host ' Installation complete!'
Write-Host '============================================'
Write-Host ''
Write-Host 'Open a new terminal window (so PATH changes take effect), then run:'
Write-Host '  claude'
Write-Host ''
Write-Host 'To confirm the managed policy is actually in force:'
Write-Host '  1. Inside Claude Code, run  /status'
Write-Host '     -- the setting sources should include:'
Write-Host '        Enterprise managed settings (file)'
Write-Host '  2. Run  claude doctor'
Write-Host '     -- reports any settings entries that were dropped as invalid.'
Write-Host '  3. Run  claude mcp list'
Write-Host '     -- should list DFCI-web-mcp only.'
Write-Host ''
Write-Host 'If /status does NOT show the managed source, a higher-precedence managed'
Write-Host 'source is overriding it (a Group Policy / Intune registry policy, or'
Write-Host 'server-managed settings from the admin console). Managed sources do not'
Write-Host 'merge -- the highest one wins.'
Write-Host ''
