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
echo Fetching configuration from GitHub...

:: Use PowerShell to fetch and parse JSON, then process each server configuration
powershell -NoProfile -Command ^
    "try { ^
        $json = (Invoke-WebRequest -Uri '%JSON_URL%' -UseBasicParsing).Content | ConvertFrom-Json; ^
        $json | Get-Member -MemberType NoteProperty | ForEach-Object { ^
            $server = $json.($_.Name); ^
            $ip = $server.IP; ^
            if ($server.HOSTS_LIST -is [string]) { ^
                $hosts = @($server.HOSTS_LIST); ^
            } else { ^
                $hosts = $server.HOSTS_LIST; ^
            } ^
            foreach ($host in $hosts) { ^
                $hostsTrimmed = $host.Trim(); ^
                $found = @(Get-Content '%HOSTS_FILE%' | Select-String -Pattern \"\b$([regex]::Escape($hostsTrimmed))\b\" -Quiet); ^
                if ($found -eq $null -or $found -eq $false) { ^
                    Add-Content -Path '%HOSTS_FILE%' -Value \"`$ip`t`$hostsTrimmed\"; ^
                    Write-Host \"Adding: `$ip    `$hostsTrimmed\"; ^
                } else { ^
                    Write-Host \"Already present: `$hostsTrimmed\"; ^
                } ^
            } ^
        } ^
    } catch { ^
        Write-Host \"Error: $_\"; ^
        exit 1; ^
    }"
if %errorlevel% neq 0 (
	echo Error processing configuration. Please check your GitHub URL and JSON format.
	pause
	exit /b 1
)

echo.
echo Creating desktop shortcuts from configuration...

:: Use PowerShell to create shortcuts from JSON
powershell -NoProfile -Command ^
    "try { ^
        $json = (Invoke-WebRequest -Uri '%JSON_URL%' -UseBasicParsing).Content | ConvertFrom-Json; ^
        $desktopPath = [Environment]::GetFolderPath('Desktop'); ^
        $json | Get-Member -MemberType NoteProperty | ForEach-Object { ^
            $server = $json.($_.Name); ^
            if ($server.SHORTCUTS) { ^
                $server.SHORTCUTS | Get-Member -MemberType NoteProperty | ForEach-Object { ^
                    $shortcutName = $_.Name; ^
                    $shortcutUrl = $server.SHORTCUTS.($shortcutName); ^
                    $shortcutPath = Join-Path $desktopPath \"$shortcutName.url\"; ^
                    $shortcutContent = \"[InternetShortcut]\`nURL=$shortcutUrl\"; ^
                    Set-Content -Path $shortcutPath -Value $shortcutContent -Force; ^
                    Write-Host \"Shortcut created: $shortcutPath -> $shortcutUrl\"; ^
                } ^
            } ^
        } ^
    } catch { ^
        Write-Host \"Error creating shortcuts: $_\"; ^
    }"

echo.
echo All done.
pause

