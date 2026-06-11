@echo off
:: shellish — Windows entry point
:: Delegates everything to shellish-cmd.js via Node.js. We keep the
:: version string local so `shellish.cmd --version` works even when
:: Node is not yet on PATH; everything else is a single Node call so
:: we do not depend on cmd.exe argument parsing edge cases.

:: Inline version first: avoid Node/PATH lookup for a constant.
if /i "%~1"=="version" goto :version
if /i "%~1"=="--version" goto :version
if /i "%~1"=="-v" goto :version

:: Resolve paths relative to this .cmd file
set "SHELLISH_ROOT=%~dp0.."
set "SHELLISH_LIB=%SHELLISH_ROOT%\lib"

:: Prefer a bundled Node runtime if present; otherwise require node on PATH.
set "NODE_EXE=%SHELLISH_ROOT%\node\node.exe"
if not exist "%NODE_EXE%" (
    where node >nul 2>nul
    if errorlevel 1 (
        echo shellish: Node.js not found. Please install Node.js and add it to PATH. 1>&2
        echo shellish: https://nodejs.org 1>&2
        exit /b 1
    )
    set "NODE_EXE=node"
)

:: Everything else (status, config, help, install-hook, --from-shell,
:: or a raw natural-language prompt) is handled by shellish-cmd.js.
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" %*
goto :eof

:version
echo shellish v0.1.0
goto :eof
