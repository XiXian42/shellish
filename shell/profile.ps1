# shellish — PowerShell hook
# Added to $PROFILE by install.ps1
#
# Intercepts unknown commands and routes natural-language input to shellish.

$_shellishBin = (Get-Command shellish.cmd -ErrorAction SilentlyContinue)?.Source

if ($_shellishBin) {
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param([string]$Name, [System.Management.Automation.CommandLookupEventArgs]$EventArgs)

        # Pass the raw input line to shellish
        & shellish.cmd --from-shell $Name
        $exitCode = $LASTEXITCODE

        # Tell PowerShell not to show its own "not recognized" error
        $EventArgs.StopSearch = $true

        # Preserve exit code in $?
        if ($exitCode -ne 0) {
            $global:LASTEXITCODE = $exitCode
        }
    }
}
