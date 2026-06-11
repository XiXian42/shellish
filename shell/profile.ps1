# shellish — PowerShell hook
# Added to $PROFILE by install.ps1 / shellish install-hook
# Syntax target: Windows PowerShell 5.1+ and PowerShell 7+.
#
# Design:
#   - PATH exposes shellish.cmd as the Windows fallback CLI.
#   - This PowerShell profile bypasses cmd.exe entirely: it defines a
#     `shellish` function and the PSReadLine hook calls Node directly.
#   - No same-name shellish.ps1 entry point is used, avoiding
#     ExecutionPolicy conflicts and .cmd argument parsing on the hook path.

# Resolve install root. $MyInvocation works when dot-sourced from a profile;
# fall back to walking up from CWD for CI/source-from-repo cases.
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
    $probe = Get-Location
    $_shellishRoot = $null
    for ($i = 0; $i -lt 8; $i++) {
        if (Test-Path (Join-Path $probe 'lib\shellish-cmd.js') -PathType Leaf) {
            $_shellishRoot = $probe
            break
        }
        $parent = Split-Path -Parent $probe
        if (-not $parent -or $parent -eq $probe) { break }
        $probe = $parent
    }
    if (-not $_shellishRoot) { $_shellishRoot = Get-Location }
}

$script:ShellishRoot = $_shellishRoot
$script:ShellishCli  = Join-Path $script:ShellishRoot 'lib\shellish-cmd.js'
$script:ShellishNode = Join-Path $script:ShellishRoot 'node\node.exe'
if (-not (Test-Path $script:ShellishNode)) { $script:ShellishNode = 'node' }
$script:ShellishBinDir = Join-Path $script:ShellishRoot 'bin'

if (Test-Path $script:ShellishCli) {
    # UTF-8 console for CJK/emoji on Windows PowerShell 5.1.
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding  = $utf8
        [Console]::OutputEncoding = $utf8
        $OutputEncoding           = $utf8
    } catch {
        # non-fatal
    }

    # Prefer the real install bin for fallback commands such as shellish.cmd
    # and shellish-trash.cmd. Use the platform PATH separator (';' Windows,
    # ':' Unix) so sourcing this profile in pwsh on macOS/Linux for tests
    # does not corrupt PATH.
    if (Test-Path $script:ShellishBinDir) {
        $_sep = [System.IO.Path]::PathSeparator
        $pathParts = @($env:PATH -split [regex]::Escape($_sep) | Where-Object { $_ -and ($_ -ne $script:ShellishBinDir) })
        $env:PATH = (@($script:ShellishBinDir) + $pathParts) -join $_sep
    }

    function global:shellish {
        & $script:ShellishNode $script:ShellishCli @args
        $global:LASTEXITCODE = $LASTEXITCODE
    }

    function global:Invoke-ShellishFromLine([string]$line) {
        & $script:ShellishNode $script:ShellishCli --from-shell $line
        $global:LASTEXITCODE = $LASTEXITCODE
    }

    function global:Test-ShellishShouldHandle([string]$line) {
        if ([string]::IsNullOrWhiteSpace($line)) { return $false }
        if ($line -match '^\s*[|&;]\s*$' -or $line -match '^\s*[<>]') { return $false }
        if ($line -match '^\s*[&.]\s') { return $false }
        if ($line -match '^\s*\$\w+\s*=') { return $false }
        if ($line -match '^\s*[\(\{]')    { return $false }
        if ($line -match '^\s*(\.\\|\.\/|~[\\/]|[A-Za-z]:[\\/]|\\\\)') { return $false }
        if ($line -match '^\s*"[^"]+"\s*(?:$|-)') { return $false }
        if ($line -match "^\s*'[^']+'\s*(?:$|-)") { return $false }

        $first = ($line.Trim() -split '\s+', 2)[0]
        if ([string]::IsNullOrEmpty($first)) { return $false }

        $keywords = @(
            'if','else','elseif','for','foreach','while','do','until',
            'switch','try','catch','finally','throw','return','exit',
            'function','filter','workflow','class','enum','using',
            'param','begin','process','end','dynamicparam','data',
            'in','break','continue','trap'
        )
        if ($keywords -contains $first) { return $false }

        # Suspend our own CommandNotFoundAction during the probe: GetCommand
        # fires it, and the action supplies a CommandScriptBlock — which makes
        # every unknown name look like a real command and the classifier
        # answer "known" for all natural-language input.
        $cnfAction = $ExecutionContext.InvokeCommand.CommandNotFoundAction
        $ExecutionContext.InvokeCommand.CommandNotFoundAction = $null
        try {
            $cmd = $ExecutionContext.SessionState.InvokeCommand.GetCommand($first, 'All')
        } finally {
            $ExecutionContext.InvokeCommand.CommandNotFoundAction = $cnfAction
        }
        return ($null -eq $cmd)
    }

    # Preferred: PSReadLine Enter handler preserves the full line.
    $psrl = Get-Module -Name PSReadLine -ErrorAction SilentlyContinue
    if (-not $psrl) {
        try { $psrl = Import-Module PSReadLine -PassThru -ErrorAction Stop } catch { $psrl = $null }
    }
    if ($psrl) {
        $alreadyBound = $false
        try {
            # Field layout differs across PSReadLine versions: newer ones
            # surface the brief description as .Function (with .Description
            # holding the long text); older ones put it in .Description.
            $alreadyBound = [bool] (Get-PSReadLineKeyHandler -Bound |
                Where-Object { $_.Key -eq 'Enter' -and (
                    $_.Function -eq 'shellish::enter' -or $_.Description -eq 'shellish::enter') })
        } catch { $alreadyBound = $false }

        if (-not $alreadyBound) {
            $handler = {
                param($key, $arg)
                $line = $null
                $cursor = $null
                [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor) | Out-Null

                if (Test-ShellishShouldHandle $line) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, '') | Out-Null
                    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() | Out-Null
                    Invoke-ShellishFromLine $line
                    return
                }
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() | Out-Null
            }

            try {
                Set-PSReadLineKeyHandler -Key Enter -BriefDescription 'shellish::enter' -LongDescription 'Divert natural-language input to shellish' -ScriptBlock $handler
            } catch {
                try {
                    Set-PSReadLineKeyHandler -Chord Enter -BriefDescription 'shellish::enter' -LongDescription 'Divert natural-language input to shellish' -ScriptBlock $handler
                } catch {
                    # Fallback remains CommandNotFoundAction.
                }
            }
        }
    }

    # Last-resort fallback. Hosts without PSReadLine cannot recover full
    # multi-token input; this is an API limitation.
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param([string]$Name, [System.Management.Automation.CommandLookupEventArgs]$EventArgs)
        if ($Name -like 'Get-*') { return }
        if ([string]::IsNullOrWhiteSpace($Name)) { return }

        $EventArgs.CommandScriptBlock = {
            $line = (@($Name) + @($args)) -join ' '
            Invoke-ShellishFromLine $line
        }.GetNewClosure()
    }

    # ── Wrap PS cmdlet/alias removers to route through safe-rm ──────────
    # PowerShell resolves `rm` / `del` / `erase` / `rmdir` / `rd` as
    # aliases to the `Remove-Item` cmdlet — it never consults PATH, so
    # the rm.cmd shim injected by run.js is invisible to interactive PS
    # sessions. We shadow the cmdlet with a global function that
    # forwards all arguments verbatim to `shellish-trash` (resolved via
    # PATH: the agent's session-aware shim when present, bin\
    # shellish-trash.cmd otherwise). The function does not implement
    # pipeline binding, so `Get-ChildItem | Remove-Item` skips the
    # wrapper and hits the real cmdlet.
    #
    # Scripts and modules that need real deletion opt out explicitly with
    # the fully qualified name `Microsoft.PowerShell.Management\Remove-Item`.
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
        $global:LASTEXITCODE = $LASTEXITCODE
    }
    # The aliases `rm`, `del`, `erase`, `rmdir`, `rd` all resolve to
    # `Remove-Item`. We rebind them to our wrapper so they hit the
    # wrapper regardless of whether the user typed the alias or the
    # cmdlet name.
    #
    # Some of these ship with the AllScope option (which ones varies by
    # PS version/platform — e.g. `del` on pwsh). AllScope can never be
    # removed from an existing alias, so a plain Set-Alias on it raises
    # an error — fatal under $ErrorActionPreference = 'Stop' (the GitHub
    # Actions default), killing the whole profile load. Preserve the
    # option when present; the try/catch keeps one stubborn alias from
    # breaking shell startup.
    foreach ($_shellishAlias in 'rm','del','erase','rmdir','rd') {
        try {
            $_existing = Get-Alias -Name $_shellishAlias -ErrorAction SilentlyContinue
            if ($_existing -and ($_existing.Options -band [System.Management.Automation.ScopedItemOptions]::AllScope)) {
                Set-Alias -Name $_shellishAlias -Value Remove-Item -Scope Global -Force -Option AllScope
            } else {
                Set-Alias -Name $_shellishAlias -Value Remove-Item -Scope Global -Force
            }
        } catch {
            Write-Verbose "shellish: could not rebind alias '$_shellishAlias': $_"
        }
    }
}
