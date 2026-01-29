@echo off
rem ------------------------------------------------------------------
rem AddToHost.bat — append host entries to Windows hosts file (idempotent)
rem Usage: run as administrator; script will re-run itself elevated if needed
rem ------------------------------------------------------------------

setlocal EnableDelayedExpansion
set HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts
set IP=10.67.1.77
set HOSTS_LIST=cap-tel.local cloud.cap-tel.local ottercloud.io captel.ottercloud.io captel-metabase.ottercloud.io captel-vpn.ottercloud.io captel-nextcloud.ottercloud.io

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
for %%H in (%HOSTS_LIST%) do (
	:: Check if hostname is already present (any line containing the hostname)
	findstr /i /c:"%%H" "%HOSTS_FILE%" >nul 2>&1
	if errorlevel 1 (
		echo Adding: %IP%    %%H
		>>"%HOSTS_FILE%" echo %IP%    %%H
	) else (
		echo Already present: %%H
	)
)

echo.
echo Creating desktop shortcut to NextCloud...
set SHORTCUT=%USERPROFILE%\Desktop\NextCloud.url
(
	echo [InternetShortcut]
	echo URL=https://captel.ottercloud.io/nextcloud
) > "%SHORTCUT%"
echo Shortcut created: %SHORTCUT%

echo.
echo All done.
pause

