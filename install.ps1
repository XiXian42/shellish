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
    Microsoft.PowerShell.Management\Remove-Item -Recurse -Force $INSTALL_DIR
}

# Windows installer intentionally uses the GitHub zip archive instead of git.
# This avoids requiring Git, avoids PowerShell 5.1 native-stderr quirks, and
# avoids corporate/locked-down machines trying to install extra tooling.
$zip = Join-Path $env:TEMP "shellish.zip"
$src = Join-Path $env:TEMP "shellish-src"
if (Test-Path $zip) { Microsoft.PowerShell.Management\Remove-Item $zip -Force }
if (Test-Path $src) { Microsoft.PowerShell.Management\Remove-Item -Recurse -Force $src }

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
    if (Test-Path $zip) { Microsoft.PowerShell.Management\Remove-Item $zip -Force }
    if (Test-Path $src) { Microsoft.PowerShell.Management\Remove-Item -Recurse -Force $src }
}

# cmd.exe requires CRLF: with LF-only batch files the parser's label/goto
# scanning misbehaves and shellish.cmd can hang. The repo's .gitattributes
# marks *.cmd as eol=crlf (which GitHub's zip generation honors), but
# normalize here too in case the archive predates that or a proxy rewrote
# the bytes.
foreach ($cmdFile in Get-ChildItem "$INSTALL_DIR\bin\*.cmd" -ErrorAction SilentlyContinue) {
    $raw = [System.IO.File]::ReadAllText($cmdFile.FullName)
    $crlf = $raw -replace "`r`n", "`n" -replace "`n", "`r`n"
    if ($crlf -ne $raw) {
        [System.IO.File]::WriteAllText($cmdFile.FullName, $crlf, (New-Object System.Text.UTF8Encoding($false)))
        Write-Dim "Normalized line endings: $($cmdFile.Name)"
    }
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
                Microsoft.PowerShell.Management\Remove-Item $p -Force
                Write-Ok "Removed stale shellish shim: $p"
            } catch {
                Write-Warn "Could not remove stale shim ${p}: $($_.Exception.Message)"
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

# Non-interactive: stdin is redirected (e.g. `irm ... | iex`). Decide
# based on the *actual* agents installed on the user's machine, not
# on a hard-coded preference order. The plan:
#   1. Probe every detected agent with `--version` (5s timeout each)
#      to figure out which ones actually launch.
#   2. If exactly one is healthy, pick it. That is the user's real
#      setup; we should respect it instead of preferring pi.
#   3. If multiple are healthy and the install is interactive, ask
#      the user to choose. If non-interactive, pick the first healthy
#      one (in the order they were detected, which roughly matches
#      PATH order) and warn the user that the choice may not be
#      what they want.
#   4. If none are healthy (all probes timed out / errored), fall
#      back to the first detected agent so the install still
#      completes; the user will see the obvious failure on first run.
function Test-AgentHealthy([string]$a) {
    try {
        $p = Start-Process -FilePath $a -ArgumentList '--version' `
            -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\shellish-probe-$a.txt" `
            -RedirectStandardError "$env:TEMP\shellish-probe-$a.err"
        $exited = $p.WaitForExit(5000)
        if (-not $exited) { try { $p.Kill() } catch { }; return $false }
        return ($p.ExitCode -eq 0)
    } catch { return $false }
}

$healthy = @()
foreach ($a in $agents) {
    Write-Dim "Probing $a ..."
    if (Test-AgentHealthy $a) {
        $healthy += $a
        Write-Dim "  $a responds"
    } else {
        Write-Dim "  $a probe failed (timed out or errored)"
    }
}

$chosen = $null
$nonInteractive = [Console]::IsInputRedirected
if ($nonInteractive) {
    Write-Dim "Non-interactive install (stdin is redirected). Picking from healthy agents on this machine."
    if ($healthy.Count -eq 1) {
        # Only one usable agent: that is the user's real setup.
        $chosen = $healthy[0]
        Write-Dim "Only $chosen responded; using it."
    } elseif ($healthy.Count -gt 1) {
        $chosen = $healthy[0]
        Write-Warn "Multiple agents respond on this machine: $($healthy -join ', ')."
        Write-Warn "Non-interactive install picked $chosen. To choose another, run 'shellish config' after install."
    } else {
        # No agent responded. Pick the first detected agent so the
        # install completes; user will hit the obvious failure on
        # first run and the README / status will guide them.
        $chosen = $agents[0]
        Write-Warn "No agent responded to '--version' on this machine."
        Write-Warn "Defaulting to $chosen. You will need to authenticate it before shellish can use it."
    }
} else {
    # Interactive: list agents (mark healthy ones), let user pick.
    if ($healthy.Count -gt 0 -and $healthy.Count -lt $agents.Count) {
        Write-Host "  Agents that respond to --version: " -NoNewline
        Write-Host ($healthy -join ', ') -ForegroundColor Green
        Write-Host "  Other detected agents did not respond and may need authentication."
        Write-Host ""
    }
    $choiceRaw = ''
    try {
        $choiceRaw = Read-Host "  Your choice [1-$($agents.Count), default=1]"
    } catch { $choiceRaw = '' }
    $choice = "$choiceRaw".Trim()
    $digits = ($choice -replace '[^\d]', '')
    if ([string]::IsNullOrWhiteSpace($digits)) { $idx = 0 }
    else { $idx = [int]$digits - 1 }
    if ($idx -lt 0 -or $idx -ge $agents.Count) { $idx = 0 }
    $chosen = $agents[$idx]
}

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
# Resolve the real Documents folder: with OneDrive/folder redirection,
# %USERPROFILE%\Documents may be read-only (or simply not where PowerShell
# reads $PROFILE from). GetFolderPath follows the redirection.
$docsDirs = @()
try { $docsDirs += [Environment]::GetFolderPath('MyDocuments') } catch { }
$docsDirs += "$env:USERPROFILE\Documents"
$docsDirs = @($docsDirs | Where-Object { $_ } | Select-Object -Unique)
$profileFiles = @(
    foreach ($d in $docsDirs) {
        Join-Path $d 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
        Join-Path $d 'PowerShell\Microsoft.PowerShell_profile.ps1'
    }
) | Select-Object -Unique
$hookLine = "`n$HOOK_BEGIN`n. `"$INSTALL_DIR\shell\profile.ps1`"`n$HOOK_END`n"
$hookInstalled = $false
$hookSkipped   = @()
foreach ($profileFile in $profileFiles) {
    $profileDir = Split-Path -Parent $profileFile
    try {
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
        }
        $existing = if (Test-Path $profileFile) { Get-Content $profileFile -Raw } else { '' }
        $cleaned  = Remove-ShellishHookBlock $existing
        Write-Utf8NoBom $profileFile ($cleaned + $hookLine)
        Write-Ok "Hook installed in $profileFile"
        $hookInstalled = $true
    } catch {
        Write-Warn "Could not write profile ${profileFile}: $($_.Exception.Message)"
        $hookSkipped += $profileFile
    }
}
if (-not $hookInstalled) {
    Write-Host ""
    Write-Warn "PowerShell profile could not be auto-installed (permission denied or path missing)."
    Write-Dim "Profile paths tried:"
    foreach ($p in $hookSkipped) { Write-Dim "  - $p" }
    Write-Dim "Fix one of these, then run:"
    Write-Dim "  shellish install-hook"
    Write-Dim "Or manually add this line to your PowerShell profile:"
    Write-Dim "  . `"$INSTALL_DIR\shell\profile.ps1`""
    Write-Host ""
}

# ── execution policy guidance ─────────────────────────────────────────────────
# If the policy is Restricted / AllSigned, our install hook will silently
# no-op and `shellish` will look broken. Probe the policy and, if it
# blocks, print a REQUIRED-STEP banner so the user does not miss it.
$policyBlocks = $false
$effectivePolicy = $null
$currentUserPolicy = $null
try {
    $effectivePolicy   = Get-ExecutionPolicy
    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($effectivePolicy -in @('Restricted', 'AllSigned') -or $currentUserPolicy -in @('Restricted', 'AllSigned')) {
        $policyBlocks = $true
    }
} catch { }
if ($policyBlocks) {
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host "  ! REQUIRED STEP — PowerShell execution policy" -ForegroundColor Yellow
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Current policy: $effectivePolicy (user: $currentUserPolicy)" -ForegroundColor Yellow
    Write-Host "  shellish scripts are unsigned; Windows PowerShell will refuse"
    Write-Host "  to load them with the above policy. Run ONE of these in a"
    Write-Host "  PowerShell window (the first is recommended):"
    Write-Host ""
    Write-Host "    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor White
    Write-Host ""
    Write-Host "  or, for a one-time test without changing policy:"
    Write-Host ""
    Write-Host "    powershell -ExecutionPolicy Bypass" -ForegroundColor White
    Write-Host ""
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
