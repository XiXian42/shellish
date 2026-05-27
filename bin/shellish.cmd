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

:: Default: delegate all argument parsing to shellish-cmd.js.
:: Important: do not parse/shift --from-shell here. In batch files %* always
:: contains the original arguments, so shifting would leak --from-shell into
:: the user prompt.
node "%SHELLISH_LIB%\shellish-cmd.js" %*
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
