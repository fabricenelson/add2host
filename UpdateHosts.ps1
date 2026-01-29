param(
    [string]$JsonUrl,
    [string]$HostsFile
)

try {
    Write-Host "Fetching configuration from GitHub..."
    $json = (Invoke-WebRequest -Uri $JsonUrl -UseBasicParsing).Content | ConvertFrom-Json
    
    # Process hosts
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
            $hostsContent = Get-Content $HostsFile
            $found = $hostsContent | Select-String -Pattern "\b$([regex]::Escape($hostsTrimmed))\b" -Quiet
            
            if (-not $found) {
                Add-Content -Path $HostsFile -Value "`n$ip`t$hostsTrimmed"
                Write-Host "Adding: $ip    $hostsTrimmed"
            } else {
                Write-Host "Already present: $hostsTrimmed"
            }
        }
    }
    
    # Process shortcuts
    Write-Host ""
    Write-Host "Creating desktop shortcuts..."
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
    exit 0
}
catch {
    Write-Host "Error: $_"
    exit 1
}
