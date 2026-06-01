# shellish — PowerShell hook
# Added to $PROFILE by install.ps1 / shellish install-hook
# Syntax target: Windows PowerShell 5.1+ and PowerShell 7+.
#
# Strategy:
#   1. PSReadLine Enter handler: parse the buffer before PSReadLine dispatches
#      the line. If the first token is not a known command, divert the full
#      buffer (preserved verbatim) to shellish. Real commands flow through
#      untouched. This is the only path that recovers full multi-token input.
#   2. CommandNotFoundAction: best-effort fallback for hosts without
#      PSReadLine (rare). PS 5.1 only exposes $Name here — the rest of the
#      buffer is lost. We do what we can.

# Resolve the install root without relying on $PSScriptRoot: the latter
# is only meaningful when this file is run as a script; when the file
# is dot-sourced from the command line (CI step, . $PROFILE) it inherits
# the caller's $PSScriptRoot, which may be $null. $MyInvocation gives us
# the path of *this* script regardless of how we got here, but in early
# PS 5.1 builds it can also be empty when dot-sourced from an
# interactive session, so fall back to PWD-derived heuristics.
$_shellishScriptPath = $null
if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
    $_shellishScriptPath = $MyInvocation.MyCommand.Path
}
if (-not $_shellishScriptPath -and $PSCommandPath) {
    $_shellishScriptPath = $PSCommandPath
}
if ($_shellishScriptPath) {
    $_shellishRoot = Split-Path -Parent (Split-Path -Parent $_shellishScriptPath)
} else {
    # Last-resort: walk up from CWD looking for a sibling bin/ folder
    # that contains shellish.ps1. Catches CI run-from-anywhere cases.
    $probe = Get-Location
    $_shellishRoot = $null
    for ($i = 0; $i -lt 8; $i++) {
        if (Test-Path (Join-Path $probe 'bin\shellish.ps1') -PathType Leaf) {
            $_shellishRoot = $probe
            break
        }
        $probe = Split-Path -Parent $probe
        if (-not $probe -or $probe -eq (Split-Path -Parent $probe)) { break }
    }
    if (-not $_shellishRoot) { $_shellishRoot = Get-Location }
}
$global:_shellishBin = Join-Path $_shellishRoot 'bin\shellish.ps1'
if (-not (Test-Path $global:_shellishBin)) {
    $global:_shellishBin = Join-Path $_shellishRoot 'bin\shellish.cmd'
}
$_shellishBinDir = Split-Path -Parent $global:_shellishBin

if (Test-Path $global:_shellishBin) {
    # ── UTF-8 console ────────────────────────────────────────────────────
    # PowerShell 5.1 on non-English Windows (CP936/CP932/...) corrupts
    # CJK input and emoji in $input / Read-Host / `Out-File` defaults.
    # Switch the three relevant encodings to UTF-8 for this session.
    # We set the BOM-less variant ($false) so files we write do not gain
    # a stray BOM. Re-sourcing this profile is safe.
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding  = $utf8
        [Console]::OutputEncoding = $utf8
        $OutputEncoding           = $utf8
    } catch {
        # non-fatal
    }

    # Prefer the real install entrypoint for this PowerShell session. This avoids
    # stale/broken copies of shellish.cmd in earlier PATH directories.
    $pathParts = @($env:PATH -split ';' | Where-Object { $_ -and ($_ -ne $_shellishBinDir) })
    $env:PATH = (@($_shellishBinDir) + $pathParts) -join ';'

    # ── Helpers ────────────────────────────────────────────────────────────
    # Is the first whitespace-delimited token of a line a known command?
    # Used by the PSReadLine hook.
    function global:Test-ShellishShouldHandle([string]$line) {
        if ([string]::IsNullOrWhiteSpace($line)) { return $false }
        # Operators and redirections are commands, not natural language.
        if ($line -match '^\s*[|&;]\s*$' -or $line -match '^\s*[<>]') { return $false }
        # Call operators: . .\script.ps1 (dot-source) and & $var (call) are
        # valid PS commands, not natural language.
        if ($line -match '^\s*[&.]\s') { return $false }
        # Assignment or expression: let PS evaluate it.
        if ($line -match '^\s*\$\w+\s*=') { return $false }
        if ($line -match '^\s*[\(\{]')    { return $false }
        # Explicit paths / quoted executable paths are valid commands, not NL.
        if ($line -match '^\s*(\.\\|\.\/|~[\\/]|[A-Za-z]:[\\/]|\\\\)') { return $false }
        if ($line -match '^\s*"[^"]+"\s*(?:$|-)') { return $false }
        if ($line -match "^\s*'[^']+'\s*(?:$|-)") { return $false }
        $first = ($line.Trim() -split '\s+', 2)[0]
        if ([string]::IsNullOrEmpty($first)) { return $false }
        # PowerShell language keywords that GetCommand does not always
        # resolve. Cover the common ones explicitly so an `if (...)` or
        # `foreach (...)` line is not hijacked.
        $keywords = @(
            'if','else','elseif','for','foreach','while','do','until',
            'switch','try','catch','finally','throw','return','exit',
            'function','filter','workflow','class','enum','using',
            'param','begin','process','end','dynamicparam','data',
            'in','break','continue','trap'
        )
        if ($keywords -contains $first) { return $false }
        # Try to resolve the first token as any kind of command.
        $cmd = $ExecutionContext.SessionState.InvokeCommand.GetCommand($first, 'All')
        return ($null -eq $cmd)
    }

    function global:Invoke-ShellishFromLine([string]$line) {
        & $global:_shellishBin --from-shell $line
        $global:LASTEXITCODE = $LASTEXITCODE
    }

    # ── 1. PSReadLine Enter handler (preferred) ─────────────────────────────
    # Use it if available. PSReadLine is bundled with PowerShell 5.1+ and
    # Windows PowerShell ISE 5.1+; PS 7+ ships with it too.
    $psrl = Get-Module -Name PSReadLine -ErrorAction SilentlyContinue
    if (-not $psrl) {
        try { $psrl = Import-Module PSReadLine -PassThru -ErrorAction Stop } catch { $psrl = $null }
    }
    if ($psrl) {
        # Bind a key handler only if we have not already. PSReadLine does not
        # expose its handler table directly; the description marker is the
        # signal we use to make this idempotent.
        $alreadyBound = $false
        try {
            $alreadyBound = [bool] (Get-PSReadLineKeyHandler -Bound |
                Where-Object { $_.Key   -eq 'Enter' -and
                               $_.Description -eq 'shellish::enter' })
        } catch {
            # Get-PSReadLineKeyHandler exists since PSReadLine 1.6. If it
            # isn't there we silently fall through and try Set-PSReadLineKeyHandler.
            $alreadyBound = $false
        }
        if (-not $alreadyBound) {
            $handler = {
                param($key, $arg)

                # Pull the current buffer verbatim.
                $line = $null
                $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
                    [ref]$line, [ref]$cursor) | Out-Null

                if (Test-ShellishShouldHandle $line) {
                    # Wipe the buffer so AcceptLine does nothing, then call
                    # shellish directly with the full original line.
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
                        0, $line.Length, '') | Out-Null
                    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() | Out-Null
                    Invoke-ShellishFromLine $line
                    return
                }

                # Known command (or operator / assignment): let PSReadLine
                # dispatch normally.
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() | Out-Null
            }

            # PSReadLine 2.2+ accepts -Key; older builds (5.1 era) use -Chord.
            # Try the modern form first, fall back to -Chord.
            try {
                Set-PSReadLineKeyHandler `
                    -Key Enter `
                    -BriefDescription 'shellish::enter' `
                    -LongDescription  'Divert natural-language input to shellish' `
                    -ScriptBlock $handler
            } catch {
                try {
                    Set-PSReadLineKeyHandler `
                        -Chord Enter `
                        -BriefDescription 'shellish::enter' `
                        -LongDescription  'Divert natural-language input to shellish' `
                        -ScriptBlock $handler
                } catch {
                    # Cannot bind; CommandNotFoundAction remains as fallback.
                }
            }
        }
    }

    # ── 2. CommandNotFoundAction (last-resort fallback) ─────────────────────
    # PSReadLine 2+ bypasses this for interactive input. It only fires for
    # hosts without PSReadLine, and on PS 5.1 it only delivers $Name.
    # Documented limitation: multi-token input is unrecoverable here.
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param([string]$Name, [System.Management.Automation.CommandLookupEventArgs]$EventArgs)

        # Skip PS internal probes.
        if ($Name -like 'Get-*') { return }
        if ([string]::IsNullOrWhiteSpace($Name)) { return }

        $shellishBin = $global:_shellishBin
        $EventArgs.CommandScriptBlock = {
            $line = (@($Name) + @($args)) -join ' '
            & $shellishBin --from-shell $line
            $global:LASTEXITCODE = $LASTEXITCODE
        }.GetNewClosure()
    }

    # ── 3. Wrap PS cmdlet/alias removers to route through safe-rm ────────
    # PowerShell resolves `rm` / `del` / `erase` / `rmdir` / `rd` as
    # aliases to the `Remove-Item` cmdlet — it never consults PATH, so
    # the rm.cmd shim injected above is invisible to interactive PS
    # sessions. We shadow the cmdlet with a global function that
    # forwards all arguments verbatim to `shellish-trash`. The function
    # does not implement any pipeline binding, so legitimate use of
    # `Get-ChildItem | Remove-Item` will skip the wrapper and hit the
    # real cmdlet — see the note below for how to opt out of the
    # safety net.
    #
    # We install in the global scope so anything that uses a fully
    # qualified cmdlet name (`Microsoft.PowerShell.Management\Remove-Item`)
    # still bypasses us and works as expected. That is by design:
    # scripts and modules that need to delete files opt out explicitly.
    #
    # Idempotency: re-sourcing this profile overwrites the function
    # definitions without warning.
    function global:Remove-Item {
        # No [CmdletBinding()] on purpose: with it, PowerShell would
        # silently drop unbound common parameters like -Verbose,
        # -ErrorAction, etc. We want to forward most arguments verbatim to
        # `shellish-trash`, including any flags the user (or agent) added.
        # Exception: -WhatIf is a dry-run contract in PowerShell; never
        # convert it into a real trash operation.
        param([Parameter(ValueFromRemainingArguments=$true)] [object[]] $Args)
        $argv = @($Args)
        $hasWhatIf = $false
        $passthrough = @()
        foreach ($a in $argv) {
            $s = if ($a -is [string]) { $a } else { [string]$a }
            # Treat bare -WhatIf / -wi / -WhatIf:$true as the dry-run signal.
            if ($s -match '^-(?i:WhatIf|wi)(\$|:.*)?$') {
                $hasWhatIf = $true
                continue
            }
            $passthrough += $a
        }
        if ($hasWhatIf) {
            # Honor the dry-run contract: print what would have been trashed
            # and exit cleanly so scripts depending on -WhatIf still pass.
            $paths = @($passthrough | Where-Object { $_ -isnot [string] -or $_ -notmatch '^-' })
            if ($paths.Count -gt 0) {
                Write-Host ("WhatIf: shellish-trash " + (($paths | ForEach-Object { [string]$_ }) -join ' '))
            } else {
                Write-Host "WhatIf: shellish-trash (no paths)"
            }
            return
        }
        & shellish-trash @passthrough
    }
    # The aliases `rm`, `del`, `erase`, `rmdir`, `rd` all resolve to
    # `Remove-Item`. We rebind them to our wrapper so they hit the
    # wrapper regardless of whether the user typed the alias or the
    # cmdlet name.
    Set-Alias -Name rm     -Value Remove-Item -Scope Global -Force
    Set-Alias -Name del    -Value Remove-Item -Scope Global -Force
    Set-Alias -Name erase  -Value Remove-Item -Scope Global -Force
    Set-Alias -Name rmdir  -Value Remove-Item -Scope Global -Force
    Set-Alias -Name rd     -Value Remove-Item -Scope Global -Force
}
