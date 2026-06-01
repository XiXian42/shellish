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
    $cleaned = [regex]::Replace($src, '(?ms)\r?\n?# >>> shellish hook >>>.*?# <<< shellish hook <<<\r?\n?', "`n")
    $cleaned = [regex]::Replace($cleaned, '(?ms)\r?\n?# shellish hook\r?\n\.\s+".*?shellish[\\/]+shell[\\/]+profile\.ps1"\r?\n?', "`n")

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
) | Select-Object -Unique
foreach ($p in $profiles) { Remove-HookFromProfile $p }

# Remove install bin from PATH.
Remove-FromUserPath $BIN_DIR

# Remove installed program files.
if (Test-Path $INSTALL_DIR) {
    Microsoft.PowerShell.Management\Remove-Item -Recurse -Force $INSTALL_DIR
    Write-Ok "Removed $INSTALL_DIR"
} else {
    Write-Dim "$INSTALL_DIR not found"
}

# Warn about stale copies created by old installers, and remove any we can
# prove belong to shellish (the marker comment disambiguates from user files
# that happen to be named shellish.cmd). Pre-0.1 installers left shims in
# System32, %APPDATA%\npm, and %USERPROFILE%\bin; clean those up too.
try {
    $cmds = @(Get-Command shellish.cmd -All -ErrorAction SilentlyContinue)
    foreach ($c in $cmds) {
        if ($c.Source -and (Test-Path $c.Source)) {
            Write-Warn "shellish.cmd still exists at $($c.Source)"
            Write-Dim "If this is an old shellish shim, remove it manually."
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
                Microsoft.PowerShell.Management\Remove-Item $p -Force
                Write-Ok "Removed stale shellish shim: $p"
            } catch {
                Write-Warn "Could not remove stale shim $p: $($_.Exception.Message)"
            }
        } elseif ($content) {
            Write-Dim "Skipping non-shellish file at $p"
        }
    }
}

# Data/config is user-owned. Keep by default.
if ((Test-Path $DATA_DIR) -or (Test-Path $LEGACY_CFG)) {
    $rmData = Read-Host "  Remove shellish data/config too? [y/N]"
    if ($rmData -in @('y','Y')) {
        if (Test-Path $DATA_DIR) {
            Microsoft.PowerShell.Management\Remove-Item -Recurse -Force $DATA_DIR
            Write-Ok "Removed $DATA_DIR"
        }
        if (Test-Path $LEGACY_CFG) {
            Microsoft.PowerShell.Management\Remove-Item -Recurse -Force $LEGACY_CFG
            Write-Ok "Removed legacy config $LEGACY_CFG"
        }
    } else {
        Write-Dim "Kept data/config: $DATA_DIR"
    }
}

Write-Host ""
Write-Ok "Done. Restart PowerShell to apply changes."
Write-Host ""
