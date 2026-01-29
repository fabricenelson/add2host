@echo off
rem ------------------------------------------------------------------
rem AddToHost.bat — append host entries to Windows hosts file (idempotent)
rem Usage: run as administrator; script will re-run itself elevated if needed
rem Fetches configuration from GitHub: hostname.json
rem ------------------------------------------------------------------

setlocal EnableDelayedExpansion
set HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts
set JSON_URL=https://raw.githubusercontent.com/fabricenelson/add2host/refs/heads/main/hostname.json

:: Check for administrator privileges using net session
net session >nul 2>&1
if %errorlevel% neq 0 (
	echo Requesting administrator privileges...
	powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
	exit /b
)

echo Running as administrator — updating %HOSTS_FILE% if needed.

:: Create a timestamped backup before modifying
for /f "tokens=1-4 delims=/ " %%a in ('date /t') do set D=%%a-%%b-%%c
for /f "tokens=1-2 delims=: " %%x in ('time /t') do set T=%%x%%y
set BACKUP=%HOSTS_FILE%.backup_!D!_!T!
copy "%HOSTS_FILE%" "!BACKUP!" >nul 2>&1
if %errorlevel% equ 0 (
	echo Backup created: !BACKUP!
) else (
	echo Warning: could not create backup; proceeding anyway
)

echo.

:: Get the directory where this script is located
set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%UpdateHosts.ps1

:: Call PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -JsonUrl "%JSON_URL%" -HostsFile "%HOSTS_FILE%"
if !errorlevel! neq 0 (
	echo Error processing configuration.
	pause
	exit /b 1
)

echo.
echo All done.
pause

