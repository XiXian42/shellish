# shellish installer for Windows (PowerShell)
# Usage: irm https://raw.githubusercontent.com/XiXian42/shellish/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$VERSION    = '0.1.0'
$REPO       = 'https://github.com/XiXian42/shellish'
$INSTALL_DIR = "$env:LOCALAPPDATA\shellish"
$BIN_DIR     = "$env:LOCALAPPDATA\Microsoft\WindowsApps"  # in PATH by default on Win10+
# Alternative bin dir if WindowsApps is not writable:
$BIN_DIR_ALT = "$env:USERPROFILE\.local\bin"

function Write-Header {
    Write-Host ""
    Write-Host "  shellish v$VERSION — natural language shell agent" -ForegroundColor White
    Write-Host "  $REPO" -ForegroundColor DarkGray
    Write-Host "  ─────────────────────────────────────────────"
    Write-Host ""
}

function Write-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Err($msg)  { Write-Host "  ✗ $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "  → $msg" -ForegroundColor Cyan }
function Write-Dim($msg)  { Write-Host "    $msg" -ForegroundColor DarkGray }

Write-Header

# ── check node ────────────────────────────────────────────────────────────────
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Err "Node.js not found. Please install it from https://nodejs.org"
    exit 1
}
Write-Ok "Node.js $(node --version)"

# ── download / install ────────────────────────────────────────────────────────
Write-Info "Installing shellish to $INSTALL_DIR ..."

if (Test-Path $INSTALL_DIR) {
    Remove-Item -Recurse -Force $INSTALL_DIR
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    git clone --depth=1 $REPO $INSTALL_DIR 2>&1 | ForEach-Object { Write-Dim $_ }
} else {
    # Fallback: download zip
    $zip = "$env:TEMP\shellish.zip"
    Invoke-WebRequest "$REPO/archive/refs/heads/main.zip" -OutFile $zip
    Expand-Archive $zip "$env:TEMP\shellish-src" -Force
    Move-Item "$env:TEMP\shellish-src\shellish-main" $INSTALL_DIR
    Remove-Item $zip
}

Write-Ok "Downloaded to $INSTALL_DIR"

# ── add bin to PATH ───────────────────────────────────────────────────────────
$binSrc = "$INSTALL_DIR\bin"

# Try to place shellish.cmd somewhere already in PATH
$inPath = $false
foreach ($dir in $env:PATH.Split(';')) {
    if ($dir -and (Test-Path $dir) -and $dir -ne $binSrc) {
        try {
            Copy-Item "$binSrc\shellish.cmd" "$dir\shellish.cmd" -Force
            $inPath = $true
            Write-Ok "Installed shellish.cmd → $dir\shellish.cmd"
            break
        } catch { }
    }
}

if (-not $inPath) {
    # Add INSTALL_DIR\bin to user PATH permanently
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*$binSrc*") {
        [Environment]::SetEnvironmentVariable('PATH', "$binSrc;$userPath", 'User')
        $env:PATH = "$binSrc;$env:PATH"
        Write-Ok "Added $binSrc to user PATH"
    }
}

# ── detect agents ─────────────────────────────────────────────────────────────
$agents = @()
foreach ($a in @('pi','omp','claude','codex')) {
    if (Get-Command $a -ErrorAction SilentlyContinue) {
        $agents += $a
    }
}

if ($agents.Count -eq 0) {
    Write-Err "No supported agent found."
    Write-Dim "Install one of: pi, claude, codex, omp"
    Write-Dim "Then run: shellish config"
    exit 0
}

# ── pick agent ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ─────────────────────────────────────────────"
Write-Host ""
Write-Host "  Choose your default agent" -ForegroundColor White
Write-Host ""

$descs = @{ pi='earendil coding agent'; omp='earendil coding agent';
            claude='Claude Code — Anthropic'; codex='Codex CLI — OpenAI' }
for ($i = 0; $i -lt $agents.Count; $i++) {
    $a = $agents[$i]
    Write-Host ("    {0}) {1,-10}  {2}" -f ($i+1), $a, $descs[$a]) -ForegroundColor DarkGray
}
Write-Host ""
$choice = Read-Host "  Your choice [1-$($agents.Count), default=1]"
$idx = [int]($choice -replace '\D','') - 1
if ($idx -lt 0 -or $idx -ge $agents.Count) { $idx = 0 }
$chosen = $agents[$idx]

# ── save config ───────────────────────────────────────────────────────────────
$cfgDir = "$env:USERPROFILE\.config\shellish"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
@"
agent=$chosen
confirm_danger=ask
"@ | Set-Content "$cfgDir\config"

Write-Ok "Default agent: $chosen"
Write-Ok "Delete behaviour: ask (prompt + move to Recycle Bin)"

# ── install PowerShell hook ───────────────────────────────────────────────────
$profileDir  = Split-Path $PROFILE
$profileFile = $PROFILE
New-Item -ItemType Directory -Force $profileDir | Out-Null

$hookLine = "`n# shellish hook`n. `"$INSTALL_DIR\shell\profile.ps1`"`n"

if (Test-Path $profileFile) {
    $existing = Get-Content $profileFile -Raw
    if ($existing -like '*shellish*') {
        Write-Ok "Hook already present in $profileFile"
    } else {
        Add-Content $profileFile $hookLine
        Write-Ok "Hook added to $profileFile"
    }
} else {
    Set-Content $profileFile $hookLine
    Write-Ok "Created $profileFile with shellish hook"
}

# ── done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ─────────────────────────────────────────────"
Write-Host ""
Write-Host "  shellish installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Other commands:"
Write-Dim "shellish config        — change agent or settings"
Write-Dim "shellish status        — show current config"
Write-Dim "shellish uninstall-hook — remove PowerShell hook"
Write-Host ""
Write-Host "  ─────────────────────────────────────────────"
Write-Host ""
Write-Host "  Next steps" -ForegroundColor White
Write-Host "    1. Restart PowerShell"
Write-Host '    2. Try it:'
Write-Host '       shellish "list all png files in this directory"' -ForegroundColor Cyan
Write-Host '       or just type at the prompt:'
Write-Host '       list all png files in this directory' -ForegroundColor Cyan
Write-Host ""
