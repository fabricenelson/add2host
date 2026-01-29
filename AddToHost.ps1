#Requires -RunAsAdministrator

param(
    [string]$JsonUrl = "https://raw.githubusercontent.com/fabricenelson/add2host/refs/heads/main/hostname.json"
)

# Check if running as administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Requesting administrator privileges..."
    $scriptPath = $PSCommandPath
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

$HOSTS_FILE = "$env:SystemRoot\System32\drivers\etc\hosts"

try {
    Write-Host "Running as administrator — updating $HOSTS_FILE if needed."
    Write-Host ""
    
    # Create a timestamped backup
    $timestamp = Get-Date -Format "ddd-MM-dd_HHmm"
    $BACKUP = "$HOSTS_FILE.backup_$timestamp"
    
    Copy-Item -Path $HOSTS_FILE -Destination $BACKUP -ErrorAction SilentlyContinue
    if ($?) {
        Write-Host "Backup created: $BACKUP"
    } else {
        Write-Host "Warning: could not create backup; proceeding anyway"
    }
    
    Write-Host ""
    Write-Host "Fetching configuration from GitHub..."
    
    # Fetch JSON from GitHub
    $json = (Invoke-WebRequest -Uri $JsonUrl -UseBasicParsing).Content | ConvertFrom-Json
    
    # Process hosts entries
    Write-Host ""
    Write-Host "Processing hosts entries..."
    $json | Get-Member -MemberType NoteProperty | ForEach-Object {
        $server = $json.($_.Name)
        $ip = $server.IP
        
        if ($server.HOSTS_LIST -is [string]) {
            $hosts = @($server.HOSTS_LIST)
        } else {
            $hosts = $server.HOSTS_LIST
        }
        
        foreach ($host in $hosts) {
            $hostsTrimmed = $host.Trim()
            $hostsContent = Get-Content $HOSTS_FILE
            $found = $hostsContent | Select-String -Pattern "\b$([regex]::Escape($hostsTrimmed))\b" -Quiet
            
            if (-not $found) {
                Add-Content -Path $HOSTS_FILE -Value "`n$ip`t$hostsTrimmed"
                Write-Host "Adding: $ip    $hostsTrimmed"
            } else {
                Write-Host "Already present: $hostsTrimmed"
            }
        }
    }
    
    # Process shortcuts
    Write-Host ""
    Write-Host "Creating desktop shortcuts from configuration..."
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    
    $json | Get-Member -MemberType NoteProperty | ForEach-Object {
        $server = $json.($_.Name)
        if ($server.SHORTCUTS) {
            $server.SHORTCUTS | Get-Member -MemberType NoteProperty | ForEach-Object {
                $shortcutName = $_.Name
                $shortcutUrl = $server.SHORTCUTS.($shortcutName)
                $shortcutPath = Join-Path $desktopPath "$shortcutName.url"
                $shortcutContent = "[InternetShortcut]`nURL=$shortcutUrl"
                Set-Content -Path $shortcutPath -Value $shortcutContent -Force
                Write-Host "Shortcut created: $shortcutPath -> $shortcutUrl"
            }
        }
    }
    
    Write-Host ""
    Write-Host "All done."
}
catch {
    Write-Host "Error: $_"
    exit 1
}
