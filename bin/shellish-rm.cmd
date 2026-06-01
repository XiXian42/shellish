@echo off
:: alias for shellish-trash
set "SHELLISH_ROOT=%~dp0.."
set "NODE_EXE=%SHELLISH_ROOT%\node\node.exe"
if not exist "%NODE_EXE%" set "NODE_EXE=node"
"%NODE_EXE%" "%SHELLISH_ROOT%\lib\safe-rm.js" %*
