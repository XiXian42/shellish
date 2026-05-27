# shellish — PowerShell hook
# Added to $PROFILE by install.ps1
#
# Intercepts unknown commands and routes natural-language input to shellish.
# Syntax target: Windows PowerShell 5.1+ and PowerShell 7+.

$_shellishRoot = Split-Path -Parent $PSScriptRoot
$global:_shellishBin = Join-Path $_shellishRoot 'bin\shellish.cmd'
$_shellishBinDir = Split-Path -Parent $global:_shellishBin

if (Test-Path $global:_shellishBin) {
    # Prefer the real install entrypoint for this PowerShell session. This avoids
    # stale/broken copies of shellish.cmd in earlier PATH directories.
    $pathParts = @($env:PATH -split ';' | Where-Object { $_ -and ($_ -ne $_shellishBinDir) })
    $env:PATH = (@($_shellishBinDir) + $pathParts) -join ';'

    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param([string]$Name, [System.Management.Automation.CommandLookupEventArgs]$EventArgs)

        # PowerShell may probe Get-<name> while resolving unknown commands.
        # Do not route those internal probes to the agent.
        if ($Name -like 'Get-*') { return }

        $unknownCommand = $Name
        $shellishBin = $global:_shellishBin

        # In Windows PowerShell 5.1, CommandNotFoundAction should provide a
        # CommandScriptBlock to replace the missing command. Side-effecting here
        # and setting StopSearch is not reliable.
        $EventArgs.CommandScriptBlock = {
            $rawInput = (@($unknownCommand) + @($args)) -join ' '
            & $shellishBin --from-shell $rawInput
            $global:LASTEXITCODE = $LASTEXITCODE
        }.GetNewClosure()
    }
}
