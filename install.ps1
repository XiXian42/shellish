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
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
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
try {
    $longPaths = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -ErrorAction SilentlyContinue
    if ($longPaths.LongPathsEnabled -ne 1) {
        Write-Warn "Windows long path support is not enabled; very deep install paths may fail."
        Write-Dim "Enable with admin PowerShell: Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1"
    }
} catch { }

# ── download / install ────────────────────────────────────────────────────────
Write-Info "Installing shellish to $INSTALL_DIR ..."

if (Test-Path $INSTALL_DIR) {
    Remove-Item -Recurse -Force $INSTALL_DIR
}

# Windows installer intentionally uses the GitHub zip archive instead of git.
# This avoids requiring Git, avoids PowerShell 5.1 native-stderr quirks, and
# avoids corporate/locked-down machines trying to install extra tooling.
$zip = Join-Path $env:TEMP "shellish.zip"
$src = Join-Path $env:TEMP "shellish-src"
if (Test-Path $zip) { Remove-Item $zip -Force }
if (Test-Path $src) { Remove-Item -Recurse -Force $src }

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest "$REPO/archive/refs/heads/main.zip" -OutFile $zip
    # Hash the archive before extraction so the user can verify integrity
    # against the GitHub commit SHA. (We do not pin to a release tag here
    # because the install URL targets main; the hash below lets a careful
    # user confirm the bytes match GitHub's main HEAD.)
    $zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash
    Write-Dim "Archive SHA256: $zipHash"
    Write-Dim "Compare with:    $REPO/commit/$zipHash"
    Expand-Archive $zip $src -Force
    Move-Item "$src\shellish-main" $INSTALL_DIR
} finally {
    if (Test-Path $zip) { Remove-Item $zip -Force }
    if (Test-Path $src) { Remove-Item -Recurse -Force $src }
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
# the real bin each session, but this helps diagnose stale copies. Pre-0.1
# installers used to copy shellish.cmd into PATH directories (System32, npm,
# %USERPROFILE%\bin) which masked newer installs. Remove any of those that
# actually look like a shellish shim — the marker comment disambiguates from
# user files that happen to be named shellish.cmd.
try {
    $cmds = @(Get-Command shellish.cmd -All -ErrorAction SilentlyContinue)
    foreach ($c in $cmds) {
        if ($c.Source -and (-not [string]::Equals($c.Source, "$binSrc\shellish.cmd", [System.StringComparison]::OrdinalIgnoreCase))) {
            Write-Dim "Note: another shellish.cmd exists at $($c.Source)"
        }
    }
} catch { }

$staleCandidates = @(
    "$env:SystemRoot\System32\shellish.cmd",
    "$env:APPDATA\npm\shellish.cmd",
    "$env:USERPROFILE\bin\shellish.cmd"
)
# Only remove files that look like *our* shim, not a coincidental
# filename. Real shellish shims reference the install path or one of
# the project URLs. `safe-rm.js` is unique to us.
$shimMarker = '(?i)(XiXian42/shellish|safe-rm\.js|shellish safe delete entry point)'
foreach ($p in $staleCandidates) {
    if (Test-Path $p) {
        $content = ''
        try { $content = Get-Content $p -Raw -ErrorAction SilentlyContinue } catch { }
        if ($content -and $content -match $shimMarker) {
            try {
                Remove-Item $p -Force
                Write-Ok "Removed stale shellish shim: $p"
            } catch {
                Write-Warn "Could not remove stale shim $p: $($_.Exception.Message)"
            }
        } elseif ($content) {
            Write-Dim "Skipping non-shellish file at $p"
        }
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
$choiceRaw = ''
try {
    if (-not [Console]::IsInputRedirected) {
        $choiceRaw = Read-Host "  Your choice [1-$($agents.Count), default=1]"
    }
} catch { $choiceRaw = '' }
$choice = "$choiceRaw".Trim()
$digits = ($choice -replace '[^\d]', '')
if ([string]::IsNullOrWhiteSpace($digits)) { $idx = 0 }
else { $idx = [int]$digits - 1 }
if ($idx -lt 0 -or $idx -ge $agents.Count) { $idx = 0 }
$chosen = $agents[$idx]

# ── save config ───────────────────────────────────────────────────────────────
$cfgDir = "$env:APPDATA\shellish"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$configText = @"
agent=$chosen
confirm_danger=ask
"@
Write-Utf8NoBom "$cfgDir\config" $configText

Write-Ok "Default agent: $chosen"
Write-Ok "Delete behaviour: ask (prompt + move to Recycle Bin)"
Write-Ok "Data directory: $env:APPDATA\shellish"

# ── install PowerShell hook ───────────────────────────────────────────────────
$HOOK_BEGIN = '# >>> shellish hook >>>'
$HOOK_END   = '# <<< shellish hook <<<'
function Remove-ShellishHookBlock($text) {
    $text = [regex]::Replace($text, '(?ms)\r?\n?# >>> shellish hook >>>.*?# <<< shellish hook <<<\r?\n?', "`n")
    $text = [regex]::Replace($text, '(?ms)\r?\n?# shellish hook\r?\n\.\s+".*?shellish[\\/]+shell[\\/]+profile\.ps1"\r?\n?', "`n")
    return $text.TrimEnd()
}
$profileFiles = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
) | Select-Object -Unique
$hookLine = "`n$HOOK_BEGIN`n. `"$INSTALL_DIR\shell\profile.ps1`"`n$HOOK_END`n"
foreach ($profileFile in $profileFiles) {
    $profileDir = Split-Path -Parent $profileFile
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
    $existing = if (Test-Path $profileFile) { Get-Content $profileFile -Raw } else { '' }
    $cleaned = Remove-ShellishHookBlock $existing
    Write-Utf8NoBom $profileFile ($cleaned + $hookLine)
    Write-Ok "Hook installed in $profileFile"
}

# ── execution policy guidance ─────────────────────────────────────────────────
try {
    $effectivePolicy = Get-ExecutionPolicy
    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($effectivePolicy -in @('Restricted', 'AllSigned') -or $currentUserPolicy -in @('Restricted', 'AllSigned')) {
        Write-Host ""
        Write-Warn "PowerShell execution policy may block the shellish hook."
        Write-Dim "Effective policy: $effectivePolicy; CurrentUser: $currentUserPolicy"
        Write-Dim "Recommended: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
        Write-Dim "Temporary test: powershell -ExecutionPolicy Bypass"
    }
} catch { }

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
