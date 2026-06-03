$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

$DatabricksHost    = 'https://adb-2613326130799470.10.azuredatabricks.net'
$DatabricksProfile = 'claude_code_workspace'
$RepoUrl           = 'https://github.com/thomas-sounack/ia-claude-code.git'
$RepoDir           = Join-Path $env:USERPROFILE 'ia-claude-code'
$DbrCliVersion     = 'v1.1.0'
$MinGitVersion     = '2.54.0'
$MinGitTag         = 'v2.54.0.windows.1'

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
Write-Host ' Step 1/8: Checking Git'
Write-Host '============================================'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'Git not found -- installing MinGit (portable, no admin)...'
    $GitDir  = Join-Path $env:USERPROFILE '.local\mingit'
    $GitBin  = Join-Path $GitDir 'cmd'
    $ZipName = "MinGit-${MinGitVersion}-64-bit.zip"
    $ZipUrl  = "https://github.com/git-for-windows/git/releases/download/${MinGitTag}/${ZipName}"

    $TmpDir = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $TmpDir | Out-Null
    try {
        Write-Host "Downloading $ZipName..."
        Invoke-WebRequest -Uri $ZipUrl -OutFile (Join-Path $TmpDir $ZipName) -UseBasicParsing
        Expand-Archive -Path (Join-Path $TmpDir $ZipName) -DestinationPath $GitDir -Force
    } finally {
        Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $UserPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if ($UserPath -notlike "*$GitBin*") {
        [System.Environment]::SetEnvironmentVariable('Path', "$UserPath;$GitBin", 'User')
    }
    $env:Path += ";$GitBin"
} else {
    Write-Host 'Git already installed -- skipping.'
}
Write-Host "Git ready: $(git --version)"

# ── Step 2: Databricks CLI ───────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 2/8: Installing Databricks CLI'
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
Write-Host ' Step 3/8: Authenticating with Databricks'
Write-Host '============================================'
Write-Host 'A browser window will open -- log in with your DFCI account.'
databricks auth login --host $DatabricksHost --profile $DatabricksProfile
Write-Host 'Databricks authentication complete.'

# ── Step 4: Python ───────────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 4/8: Checking Python'
Write-Host '============================================'

# Get-Command finds the Windows Store stub even when real Python isn't installed.
# Run python --version and check the exit code to detect the real thing.
$PythonReal = $false
try {
    $null = & python --version 2>&1
    if ($LASTEXITCODE -eq 0) { $PythonReal = $true }
} catch {}

if (-not $PythonReal) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host 'ERROR: winget is not available. Install App Installer from the Microsoft Store, then re-run.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Python not found -- installing via winget (user scope, no admin)...'
    winget install --id Python.Python.3 --scope User -e --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    Update-Path
} else {
    Write-Host 'Python already installed -- skipping.'
}
Write-Host "Python ready: $(python --version)"

# ── Step 5: Claude Code CLI ──────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 5/8: Installing Claude Code CLI'
Write-Host '============================================'

# Point Claude's installer at MinGit's bash if Git for Windows isn't in the
# standard location. MinGit ships bash.exe under usr\bin\.
$MinGitBash = Join-Path $env:USERPROFILE '.local\mingit\usr\bin\bash.exe'
if ((Test-Path $MinGitBash) -and (-not $env:CLAUDE_CODE_GIT_BASH_PATH)) {
    $env:CLAUDE_CODE_GIT_BASH_PATH = $MinGitBash
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

# ── Step 6: Clone repo ───────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 6/8: Cloning workshop repo'
Write-Host '============================================'

if (Test-Path $RepoDir) {
    Write-Host "Removing existing $RepoDir..."
    Remove-Item -Path $RepoDir -Recurse -Force
}
git clone $RepoUrl $RepoDir
Write-Host "Repo cloned to $RepoDir"

# ── Step 7: Token helpers ────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 7/8: Writing token helpers'
Write-Host '============================================'

$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

$Ps1Path = Join-Path $ClaudeDir 'databricks-token-helper.ps1'
Set-Content -Path $Ps1Path -Encoding UTF8 -Value @'
$ErrorActionPreference = "Stop"
$Profile = if ($env:DATABRICKS_CONFIG_PROFILE) { $env:DATABRICKS_CONFIG_PROFILE } else { "claude_code_workspace" }
$TokenJson = databricks auth token -p $Profile -o json
Write-Output ($TokenJson | ConvertFrom-Json).access_token
'@

$CmdPath = Join-Path $ClaudeDir 'databricks-token-helper.cmd'
Set-Content -Path $CmdPath -Encoding ASCII -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Ps1Path`""

# Patch apiKeyHelper in the cloned settings.json to the .cmd wrapper path
$SettingsFile = Join-Path $RepoDir '.claude\settings.json'
if (Test-Path $SettingsFile) {
    $Settings = Get-Content -Path $SettingsFile -Raw | ConvertFrom-Json
    if ($Settings.PSObject.Properties['apiKeyHelper']) {
        $Settings.apiKeyHelper = $CmdPath
    } else {
        $Settings | Add-Member -MemberType NoteProperty -Name 'apiKeyHelper' -Value $CmdPath
    }
    [System.IO.File]::WriteAllText($SettingsFile, ($Settings | ConvertTo-Json -Depth 20))
}

Write-Host "Token helpers written to $ClaudeDir"

# ── Step 8: hasCompletedOnboarding ───────────────────────────────────────────
Write-Host ''
Write-Host '============================================'
Write-Host ' Step 8/8: Configuring Claude Code'
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
Write-Host "Workshop repo is ready at: $RepoDir"
Write-Host ''
Write-Host 'To get started, open a new terminal and run:'
Write-Host "  cd `"$RepoDir`""
Write-Host '  claude'
Write-Host ''
