@echo off
:: shellish — Windows entry point
:: Delegates everything to run.js via Node.js

:: Resolve the lib directory relative to this .cmd file
set "SHELLISH_LIB=%~dp0..\lib"

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

:: Default: run a prompt via run.js
:: Detect --from-shell flag
set "FROM_SHELL_FLAG="
if "%~1"=="--from-shell" (
    set "FROM_SHELL_FLAG=--from-shell"
    shift
)

:: Remaining args are: <agent> is read from config; pass cwd + prompt
:: We delegate fully to shellish-run.js for prompt handling
node "%SHELLISH_LIB%\shellish-cmd.js" %FROM_SHELL_FLAG% %*
goto :eof

:version
echo shellish v0.1.0
goto :eof

:status
node "%SHELLISH_LIB%\shellish-cmd.js" status
goto :eof

:install_hook
node "%SHELLISH_LIB%\shellish-cmd.js" install-hook
goto :eof

:uninstall_hook
node "%SHELLISH_LIB%\shellish-cmd.js" uninstall-hook
goto :eof

:config
node "%SHELLISH_LIB%\shellish-cmd.js" config
goto :eof

:help
node "%SHELLISH_LIB%\shellish-cmd.js" help
goto :eof
