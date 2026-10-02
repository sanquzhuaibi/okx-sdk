@echo off
REM ASCII-only launcher. Chinese text is printed by run_backtest.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_backtest.ps1" %*
exit /b %ERRORLEVEL%
