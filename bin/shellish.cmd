@echo off
:: shellish — Windows entry point
:: Delegates everything to run.js via Node.js

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

:: Sub-commands that don't need run.js
if "%~1"=="version"        goto :version
if "%~1"=="--version"      goto :version
if "%~1"=="-v"             goto :version
if "%~1"=="status"         goto :status
if "%~1"=="install-hook"   goto :install_hook
if "%~1"=="uninstall-hook" goto :uninstall_hook
if "%~1"=="config"         goto :config
if "%~1"=="help"           goto :help
if "%~1"=="-h"             goto :help
if "%~1"=="--help"         goto :help

:: Default: delegate all argument parsing to shellish-cmd.js.
:: Important: do not parse/shift --from-shell here. In batch files %* always
:: contains the original arguments, so shifting would leak --from-shell into
:: the user prompt.
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" %*
goto :eof

:version
echo shellish v0.1.0
goto :eof

:status
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" status
goto :eof

:install_hook
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" install-hook
goto :eof

:uninstall_hook
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" uninstall-hook
goto :eof

:config
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" config
goto :eof

:help
"%NODE_EXE%" "%SHELLISH_LIB%\shellish-cmd.js" help
goto :eof
