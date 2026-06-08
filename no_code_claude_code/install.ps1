$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'


$DatabricksHost    = 'https://adb-2613326130799470.10.azuredatabricks.net'
$DatabricksProfile = 'claude_code_workspace'
$WorkDir           = Join-Path $env:USERPROFILE 'no_code_claude_code'
$DbrCliVersion     = 'v1.1.0'
$GitTag            = 'v2.54.0.windows.1'

# Refresh PATH from registry so newly installed tools are available
function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

Write-Host ''
Write-Host '============================================'
Write-Host '   Claude Code Installer -- DFCI Workshop'
Write-Host '============================================'
Write-Host ''

# ── Step 1: Git ──────────────────────────────────────────────────────────────
Write-Host '============================================'
Write-Host ' Step 1/9: Checking Git'
Write-Host '============================================'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'Git not found -- installing Git for Windows (user scope, no admin)...'
    $GitVersion = $GitTag.TrimStart('v') -replace '\.windows\.\d+$', ''
    $GitExeName = "Git-${GitVersion}-64-bit.exe"
    $GitUrl     = "https://github.com/git-for-windows/git/releases/download/${GitTag}/${GitExeName}"
    $GitTmpDir  = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $GitTmpDir | Out-Null
    $GitInstaller = Join-Path $GitTmpDir $GitExeName

    Write-Host "Downloading $GitExeName..."
    Invoke-WebRequest -Uri $GitUrl -OutFile $GitInstaller -UseBasicParsing
    Write-Host 'Installing Git (user scope)...'
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
    Write-Host 'Python not found -- installing embeddable package (no admin)...'
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
    exit 1
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

# ── Step 6/9: uv ─────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 6/9: Installing uv'
Write-Host '============================================'

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host 'uv not found -- installing...'
    powershell -ExecutionPolicy Bypass -c "irm https://astral.sh/uv/install.ps1 | iex"
    Update-Path
} else {
    Write-Host 'uv already installed -- skipping.'
}
Write-Host "uv ready: $(uv --version)"

# ── Step 7/9: Create working directory ───────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 7/9: Creating working directory'
Write-Host '============================================'

$ClaudeSubDir = Join-Path $WorkDir '.claude'
New-Item -ItemType Directory -Force -Path $ClaudeSubDir | Out-Null

# Write .mcp.json so Claude Code connects to the Databricks MCP server
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
[System.IO.File]::WriteAllText((Join-Path $WorkDir '.mcp.json'), $McpJson)

# Write .claude/settings.json with the apiKeyHelper pointing to the .cmd wrapper
$Ps1HelperPath = Join-Path $env:USERPROFILE '.claude\databricks-token-helper.ps1'
$CmdHelperPath = Join-Path $env:USERPROFILE '.claude\databricks-token-helper.cmd'

$SettingsObj = [ordered]@{
    '_version'             = '1.0.0'
    '_mode'                = 'permissive'
    'apiKeyHelper'         = $CmdHelperPath
    'companyAnnouncements' = @('Dana-Farber Cancer Institute - I&A Summit')
    'permissions'          = [ordered]@{
        'allow' = @('Bash(*)')
        'deny'  = @('WebFetch', 'WebSearch')
    }
    'env'                  = [ordered]@{
        'ANTHROPIC_MODEL'                        = 'ianda-retreat-claude-sonnet-4-6'
        'ANTHROPIC_BASE_URL'                     = 'https://adb-2613326130799470.10.azuredatabricks.net/ai-gateway/anthropic'
        'ANTHROPIC_DEFAULT_OPUS_MODEL'           = 'ianda-retreat-claude-opus-4-8'
        'ANTHROPIC_DEFAULT_SONNET_MODEL'         = 'ianda-retreat-claude-sonnet-4-6'
        'ANTHROPIC_DEFAULT_HAIKU_MODEL'          = 'ianda-retreat-claude-haiku-4-5'
        'ANTHROPIC_CUSTOM_HEADERS'               = 'x-databricks-use-coding-agent-mode: true'
        'CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS' = '1'
        'CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL'      = '1'
        'CLAUDE_CODE_SKIP_AUTH_LOGIN'            = '1'
    }
}
[System.IO.File]::WriteAllText(
    (Join-Path $ClaudeSubDir 'settings.json'),
    ($SettingsObj | ConvertTo-Json -Depth 20)
)

Write-Host "Working directory ready at: $WorkDir"

# ── Step 8/9: Token helpers ───────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 8/9: Writing token helpers'
Write-Host '============================================'

$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

Set-Content -Path $Ps1HelperPath -Encoding UTF8 -Value @'
$ErrorActionPreference = "Stop"
$Profile = if ($env:DATABRICKS_CONFIG_PROFILE) { $env:DATABRICKS_CONFIG_PROFILE } else { "claude_code_workspace" }
$TokenJson = databricks auth token -p $Profile -o json
Write-Output ($TokenJson | ConvertFrom-Json).access_token
'@

Set-Content -Path $CmdHelperPath -Encoding ASCII -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Ps1HelperPath`""

Write-Host "Token helpers written to $ClaudeDir"

# ── Step 9/9: hasCompletedOnboarding ─────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 9/9: Configuring Claude Code'
Write-Host '============================================'

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

Write-Host ''
Write-Host '============================================'
Write-Host ' Installation complete!'
Write-Host '============================================'
Write-Host ''
Write-Host "Working directory is ready at: $WorkDir"
Write-Host ''
Write-Host 'To get started, open a new terminal and run:'
Write-Host "  cd `"$WorkDir`""
Write-Host '  claude'
Write-Host ''
