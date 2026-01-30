@echo off
setlocal EnableDelayedExpansion

:: --------------------------------------------------------------------------------
:: AddToHost.bat - Dynamic Host Updater
:: --------------------------------------------------------------------------------

:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Find the start of the PowerShell content
set "MARKER=::POWERSHELL_STARTS_HERE"
for /f "delims=:" %%N in ('findstr /n /b "%MARKER%" "%~f0"') do set "SKIP_LINES=%%N"

if not defined SKIP_LINES (
    echo Error: Could not find PowerShell section in script.
    pause
    exit /b 1
)

:: Extract PowerShell script to a temp file
set "PS_SCRIPT=%TEMP%\Add2Host_%RANDOM%.ps1"
more +%SKIP_LINES% "%~f0" > "%PS_SCRIPT%"

:: Run the PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "PS_EXIT_CODE=%errorlevel%"

:: Cleanup
if exist "%PS_SCRIPT%" del "%PS_SCRIPT%"

echo.
if %PS_EXIT_CODE% equ 0 (
    echo [SUCCESS] Script finished successfully.
) else (
    echo [ERROR] Script failed with exit code %PS_EXIT_CODE%.
)
pause
exit /b %PS_EXIT_CODE%

::POWERSHELL_STARTS_HERE
# PowerShell Script starts here
$jsonUrl = "https://raw.githubusercontent.com/fabricenelson/add2host/refs/heads/main/hostname.json"
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$desktop = [Environment]::GetFolderPath("Desktop")

Write-Host "Fetching configuration from $jsonUrl..." -ForegroundColor Cyan

try {
    # Force TLS 1.2 usage for GitHub
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $content = Invoke-RestMethod -Uri $jsonUrl -ErrorAction Stop
} catch {
    Write-Error "Failed to download JSON configuration. Error: $_"
    exit 1
}

# Ensure we have an object
if ($content -is [string]) {
    try {
        $data = $content | ConvertFrom-Json
    } catch {
        Write-Error "Failed to parse JSON content."
        exit 1
    }
} else {
    $data = $content
}

if (-not $data) {
    Write-Error "JSON data is empty."
    exit 1
}

# Loop through each server entry in the JSON
foreach ($serverKey in $data.PSObject.Properties.Name) {
    if ($serverKey -eq "length" -or $serverKey -eq "count") { continue } 
    
    $server = $data.$serverKey
    $ip = $server.IP
    
    if (-not $ip) {
        Write-Warning "No IP found for $serverKey. Skipping..."
        continue
    }

    Write-Host "`nProcessing $serverKey (IP: $ip)" -ForegroundColor Green

    # --- Update HOSTS File ---
    try {
        $currentHosts = Get-Content $hostsFile -Raw -ErrorAction Stop
    } catch {
        $currentHosts = ""
    }
    
    if (-not $currentHosts) { $currentHosts = "" }
    $newlineNeeded = -not $currentHosts.EndsWith("`n")

    if ($server.HOSTS_LIST) {
        foreach ($hostname in $server.HOSTS_LIST) {
            # Check for existing mapping
            # Regex explains:
            # (?m) = multiline mode
            # ^ = start of line
            # [\s\t]* = optional whitespace
            # IP = exact IP
            # [\s\t]+ = required whitespace
            # HOSTNAME = exact hostname
            # \b = word boundary (end of hostname)
            
            if ($currentHosts -match "(?m)^[\s\t]*$([regex]::Escape($ip))[\s\t]+$([regex]::Escape($hostname))\b") {
                Write-Host "  [SKIP] Host '$hostname' is already mapped to '$ip'." -ForegroundColor DarkGray
            } elseif ($currentHosts -match "\b$([regex]::Escape($hostname))\b") {
                 Write-Host "  [WARN] Host '$hostname' exists but with a different IP. Manual check recommended." -ForegroundColor Yellow
            } else {
                 try {
                    if ($newlineNeeded) {
                        Add-Content -Path $hostsFile -Value "" -NoNewline
                        $newlineNeeded = $false
                    }
                    Add-Content -Path $hostsFile -Value "$ip`t$hostname"
                    Write-Host "  [ADD]  Mapped '$hostname' to '$ip'." -ForegroundColor Cyan
                    $currentHosts += "`r`n$ip`t$hostname"
                } catch {
                    Write-Error "  Failed to write to host file. Ensure you ran as Administrator."
                }
            }
        }
    }

    # --- Create Shortcuts ---
    if ($server.SHORTCUTS) {
        foreach ($shortcutName in $server.SHORTCUTS.PSObject.Properties.Name) {
            $url = $server.SHORTCUTS.$shortcutName
            $shortcutPath = Join-Path $desktop "$shortcutName.url"
            
            try {
                $shortcutContent = "[InternetShortcut]`r`nURL=$url"
                Set-Content -Path $shortcutPath -Value $shortcutContent
                Write-Host "  [LINK] Created desktop shortcut: $shortcutName" -ForegroundColor Cyan
            } catch {
                Write-Error "  Failed to create shortcut '$shortcutName'."
            }
        }
    }
}

Write-Host "`nOperation Complete." -ForegroundColor Green
exit 0
