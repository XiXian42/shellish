# shellish — Windows PowerShell entry point
# Keeps argument passing in PowerShell/Node instead of going through cmd.exe.

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Lib  = Join-Path $Root 'lib'
$Node = Join-Path $Root 'node\node.exe'
if (-not (Test-Path $Node)) { $Node = 'node' }

$Script = Join-Path $Lib 'shellish-cmd.js'
if (-not (Test-Path $Script)) {
    Write-Error "shellish: missing entry script at $Script. Try reinstalling: irm https://raw.githubusercontent.com/XiXian42/shellish/main/install.ps1 | iex"
    exit 2
}
if (-not (Get-Command $Node -ErrorAction SilentlyContinue)) {
    Write-Error "shellish: Node.js not found. Install from https://nodejs.org and ensure 'node' is on PATH."
    exit 3
}

try {
    & $Node $Script @args
} catch {
    Write-Error "shellish: failed to launch Node: $_"
    exit 4
}
exit $LASTEXITCODE
