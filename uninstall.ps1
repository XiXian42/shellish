# shellish uninstaller for Windows (PowerShell)
# Usage: irm https://raw.githubusercontent.com/XiXian42/shellish/main/uninstall.ps1 | iex

$ErrorActionPreference = 'Stop'

$INSTALL_DIR = "$env:LOCALAPPDATA\shellish"
$BIN_DIR     = "$INSTALL_DIR\bin"
$DATA_DIR    = "$env:APPDATA\shellish"
$LEGACY_CFG  = "$env:USERPROFILE\.config\shellish"

function Write-Header {
    Write-Host ""
    Write-Host "  shellish uninstaller" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────"
    Write-Host ""
}
function Write-Ok($msg)   { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Info($msg) { Write-Host "  → $msg" -ForegroundColor Cyan }
function Write-Dim($msg)  { Write-Host "    $msg" -ForegroundColor DarkGray }
function Write-Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

function Normalize-Path($p) {
    try { return ([System.IO.Path]::GetFullPath($p)).TrimEnd('\') }
    catch { return ($p -as [string]).TrimEnd('\') }
}

function Remove-FromUserPath($target) {
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($null -eq $userPath -or $userPath -eq '') { return }

    $targetNorm = Normalize-Path $target
    $parts = @($userPath -split ';' | Where-Object { $_ })
    $kept = @()
    $changed = $false

    foreach ($p in $parts) {
        if ([string]::Equals((Normalize-Path $p), $targetNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
            $changed = $true
        } else {
            $kept += $p
        }
    }

    if ($changed) {
        [Environment]::SetEnvironmentVariable('PATH', ($kept -join ';'), 'User')
        $env:PATH = (($env:PATH -split ';' | Where-Object {
            -not [string]::Equals((Normalize-Path $_), $targetNorm, [System.StringComparison]::OrdinalIgnoreCase)
        }) -join ';')
        Write-Ok "Removed $target from user PATH"
    }
}

function Remove-HookFromProfile($profilePath) {
    if (-not (Test-Path $profilePath)) { return }
    $src = Get-Content $profilePath -Raw
    if ($src -notlike '*shellish*') { return }

    $pattern = '(?ms)\r?\n?# shellish hook\r?\n\.\s+".*?shellish[\\/]+shell[\\/]+profile\.ps1"\r?\n?'
    $cleaned = [regex]::Replace($src, $pattern, "`n")

    if ($cleaned -ne $src) {
        Set-Content $profilePath $cleaned
        Write-Ok "Removed hook from $profilePath"
    }
}

Write-Header

$confirm = Read-Host "  Remove shellish program files and PowerShell hook? [y/N]"
if ($confirm -notin @('y','Y')) {
    Write-Host "  Aborted."
    exit 0
}

# Remove hooks from both Windows PowerShell 5.1 and PowerShell 7 profiles.
$profiles = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
)
foreach ($p in $profiles) { Remove-HookFromProfile $p }

# Remove install bin from PATH.
Remove-FromUserPath $BIN_DIR

# Remove installed program files.
if (Test-Path $INSTALL_DIR) {
    Remove-Item -Recurse -Force $INSTALL_DIR
    Write-Ok "Removed $INSTALL_DIR"
} else {
    Write-Dim "$INSTALL_DIR not found"
}

# Warn about stale copies created by old installers, but do not delete files we
# cannot prove belong to this install.
try {
    $cmds = @(Get-Command shellish.cmd -All -ErrorAction SilentlyContinue)
    foreach ($c in $cmds) {
        if ($c.Source -and (Test-Path $c.Source)) {
            Write-Warn "shellish.cmd still exists at $($c.Source)"
            Write-Dim "If this is an old shellish shim, remove it manually."
        }
    }
} catch { }

# Data/config is user-owned. Keep by default.
if ((Test-Path $DATA_DIR) -or (Test-Path $LEGACY_CFG)) {
    $rmData = Read-Host "  Remove shellish data/config too? [y/N]"
    if ($rmData -in @('y','Y')) {
        if (Test-Path $DATA_DIR) {
            Remove-Item -Recurse -Force $DATA_DIR
            Write-Ok "Removed $DATA_DIR"
        }
        if (Test-Path $LEGACY_CFG) {
            Remove-Item -Recurse -Force $LEGACY_CFG
            Write-Ok "Removed legacy config $LEGACY_CFG"
        }
    } else {
        Write-Dim "Kept data/config: $DATA_DIR"
    }
}

Write-Host ""
Write-Ok "Done. Restart PowerShell to apply changes."
Write-Host ""
