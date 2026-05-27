# shellish installer for Windows (PowerShell)
# Usage: irm https://raw.githubusercontent.com/XiXian42/shellish/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$VERSION    = '0.1.0'
$REPO       = 'https://github.com/XiXian42/shellish'
$INSTALL_DIR = "$env:LOCALAPPDATA\shellish"

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
function Write-Utf8NoBom($path, $text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $text, $enc)
}

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
    # Git writes normal progress to stderr. In Windows PowerShell 5.1,
    # piping native stderr with $ErrorActionPreference='Stop' can turn that
    # harmless progress into NativeCommandError. Run quietly and check exit.
    & git clone --quiet --depth=1 $REPO $INSTALL_DIR
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }
} else {
    # Fallback: download zip
    $zip = "$env:TEMP\shellish.zip"
    $src = "$env:TEMP\shellish-src"
    if (Test-Path $src) { Remove-Item -Recurse -Force $src }
    Invoke-WebRequest "$REPO/archive/refs/heads/main.zip" -OutFile $zip
    Expand-Archive $zip $src -Force
    Move-Item "$src\shellish-main" $INSTALL_DIR
    Remove-Item $zip -Force
    Remove-Item $src -Recurse -Force
}

Write-Ok "Downloaded to $INSTALL_DIR"

# ── add bin to PATH ───────────────────────────────────────────────────────────
$binSrc = "$INSTALL_DIR\bin"

# Do not copy bin\shellish.cmd into arbitrary PATH directories: it depends on
# ..\lib relative to its own location. Add the real bin directory instead.
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($null -eq $userPath) { $userPath = '' }
$userParts = @($userPath -split ';' | Where-Object { $_ })
$hasBin = $false
foreach ($p in $userParts) {
    if ([string]::Equals($p.TrimEnd('\'), $binSrc.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        $hasBin = $true
        break
    }
}
if (-not $hasBin) {
    [Environment]::SetEnvironmentVariable('PATH', "$binSrc;$userPath", 'User')
    Write-Ok "Added $binSrc to user PATH"
} else {
    Write-Ok "$binSrc already in user PATH"
}
# Also prefer the real bin in the current installer session.
$env:PATH = "$binSrc;$env:PATH"

# Warn if another shellish.cmd appears earlier; the profile hook will prepend
# the real bin each session, but this helps diagnose stale copies.
try {
    $cmds = @(Get-Command shellish.cmd -All -ErrorAction SilentlyContinue)
    foreach ($c in $cmds) {
        if ($c.Source -and (-not [string]::Equals($c.Source, "$binSrc\shellish.cmd", [System.StringComparison]::OrdinalIgnoreCase))) {
            Write-Dim "Note: another shellish.cmd exists at $($c.Source)"
        }
    }
} catch { }

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
$configText = @"
agent=$chosen
confirm_danger=ask
"@
Write-Utf8NoBom "$cfgDir\config" $configText

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
