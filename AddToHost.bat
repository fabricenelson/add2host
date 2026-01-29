<# :
@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Run the PowerShell portion of this script
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ($(Get-Content '%~f0' -Raw) -replace '(?s)^.*?<# :', '')"
echo.
pause
exit /b
#>

# PowerShell Script starts here
$jsonUrl = "https://raw.githubusercontent.com/fabricenelson/add2host/refs/heads/main/hostname.json"
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$desktop = [Environment]::GetFolderPath("Desktop")

Write-Host "Fetching configuration from $jsonUrl..." -ForegroundColor Cyan

try {
    $content = Invoke-RestMethod -Uri $jsonUrl
} catch {
    Write-Error "Failed to download JSON configuration. Error: $_"
    exit 1
}

# Ensure we have an object (ConvertFrom-Json might have happened automatically or not)
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

# Verify data structure
if (-not $data) {
    Write-Error "JSON data is empty."
    exit 1
}

# Loop through each server entry in the JSON
foreach ($serverKey in $data.PSObject.Properties.Name) {
    if ($serverKey -eq "length" -or $serverKey -eq "count") { continue } # Skip array properties if any
    
    $server = $data.$serverKey
    $ip = $server.IP
    
    if (-not $ip) {
        Write-Warning "No IP found for $serverKey. Skipping..."
        continue
    }

    Write-Host "`nProcessing $serverKey (IP: $ip)" -ForegroundColor Green

    # --- Update HOSTS File ---
    $currentHosts = Get-Content $hostsFile -Raw
    if (-not $currentHosts) { $currentHosts = "" }
    $newlineNeeded = -not $currentHosts.EndsWith("`n")

    foreach ($hostname in $server.HOSTS_LIST) {
        # Check if hostname matches exactly as a word boundary to avoid partial matches
        if ($currentHosts -match "(?m)^[\s\t]*$([regex]::Escape($ip))[\s\t]+$([regex]::Escape($hostname))\b") {
            Write-Host "  [SKIP] Host '$hostname' is already mapped to '$ip'." -ForegroundColor DarkGray
        } elseif ($currentHosts -match "\b$([regex]::Escape($hostname))\b") {
             Write-Host "  [WARN] Host '$hostname' exists but with a different IP. Manual check recommended." -ForegroundColor Yellow
        } else {
            # Append to hosts file
             try {
                if ($newlineNeeded) {
                    Add-Content -Path $hostsFile -Value "" -NoNewline
                    $newlineNeeded = $false
                }
                Add-Content -Path $hostsFile -Value "$ip`t$hostname"
                Write-Host "  [ADD]  Mapped '$hostname' to '$ip'." -ForegroundColor Cyan
                # Update local cache of hosts content to prevent duplicates in same run if JSON has dupes
                $currentHosts += "`r`n$ip`t$hostname"
            } catch {
                Write-Error "  Failed to write to host file. Ensure you ran as Administrator."
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
