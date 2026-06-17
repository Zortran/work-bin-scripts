#Requires -Version 5.1
<#
.SYNOPSIS
    Sets manual DNS and DoH on the active Wi-Fi connection.

.DESCRIPTION
    Finds the connected WLAN adapter, registers DoH for the configured resolvers,
    assigns manual IPv4 DNS servers, and enables encrypted DNS (DoH) via AutoUpgrade.
    Requires elevation.
#>
[CmdletBinding()]
param(
    [switch] $WhatIf,
    [string[]] $DnsServers = @('111.88.96.50', '111.88.96.51'),
    [string] $DohTemplate = 'https://xbox-dns.ru/dns-query'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ConnectedWlan {
    $raw = netsh wlan show interfaces 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "netsh wlan show interfaces failed: $raw"
    }

    $text = ($raw | Out-String)
    if ($text -notmatch '(?m)^\s*State\s*:\s*connected\s*$') {
        throw 'No active Wi-Fi connection (State is not connected).'
    }

    $netshInterfaceName = [regex]::Match($text, '(?m)^\s*Name\s*:\s*(.+)\s*$').Groups[1].Value.Trim()
    $profileName = [regex]::Match($text, '(?m)^\s*Profile\s*:\s*(.+)\s*$').Groups[1].Value.Trim()
    $interfaceGuid = [regex]::Match($text, '(?m)^\s*GUID\s*:\s*(\S+)\s*$').Groups[1].Value.Trim()

    if (-not $netshInterfaceName) {
        throw 'Could not read WLAN interface name from netsh output.'
    }
    if (-not $profileName) {
        $profileName = [regex]::Match($text, '(?m)^\s*SSID\s*:\s*(.+)\s*$').Groups[1].Value.Trim()
    }
    if (-not $profileName) {
        throw 'Could not read Wi-Fi profile name (SSID/Profile).'
    }

    $adapter = $null
    if ($interfaceGuid) {
        $guidPattern = if ($interfaceGuid -match '^\{') { $interfaceGuid } else { "{$interfaceGuid}" }
        $adapter = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceGuid -ieq $guidPattern } |
            Select-Object -First 1
    }

    [PSCustomObject]@{
        InterfaceAlias = if ($adapter) { $adapter.InterfaceAlias } else { $netshInterfaceName }
        InterfaceIndex = if ($adapter) { $adapter.ifIndex } else { $null }
        ProfileName    = $profileName
    }
}

function Set-DohServer {
    param(
        [string] $ServerAddress,
        [string] $DohTemplate,
        [switch] $WhatIf
    )

    $dohParams = @{
        ServerAddress      = $ServerAddress
        DohTemplate        = $DohTemplate
        AllowFallbackToUdp = $false
        AutoUpgrade        = $true
    }

    if ($WhatIf) {
        Write-Host "WhatIf: register DoH for $ServerAddress -> $DohTemplate (encrypted only, no UDP fallback)"
        return
    }

    $existing = Get-DnsClientDohServerAddress -ServerAddress $ServerAddress -ErrorAction SilentlyContinue
    if ($existing) {
        Set-DnsClientDohServerAddress @dohParams -ErrorAction Stop
    }
    else {
        Add-DnsClientDohServerAddress @dohParams -ErrorAction Stop
    }
}

function Set-InterfaceDns {
    param(
        [string] $InterfaceAlias,
        [Nullable[int]] $InterfaceIndex,
        [string[]] $Servers,
        [switch] $WhatIf
    )

    $target = if ($InterfaceIndex) { "index $InterfaceIndex ($InterfaceAlias)" } else { $InterfaceAlias }
    $setParams = @{ ErrorAction = 'Stop' }
    if ($InterfaceIndex) { $setParams.InterfaceIndex = $InterfaceIndex }
    else { $setParams.InterfaceAlias = $InterfaceAlias }

    if ($WhatIf) {
        Write-Host "WhatIf: Set-DnsClientServerAddress on '$target' -ServerAddresses $($Servers -join ', ')"
        return
    }

    Set-DnsClientServerAddress @setParams -ServerAddresses $Servers -Validate
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script in an elevated PowerShell session (Administrator).'
}

$wlan = Get-ConnectedWlan
Write-Verbose "WLAN interface: $($wlan.InterfaceAlias), profile: $($wlan.ProfileName)"

foreach ($server in $DnsServers) {
    Set-DohServer -ServerAddress $server -DohTemplate $DohTemplate -WhatIf:$WhatIf
}

Set-InterfaceDns `
    -InterfaceAlias $wlan.InterfaceAlias `
    -InterfaceIndex $wlan.InterfaceIndex `
    -Servers $DnsServers `
    -WhatIf:$WhatIf

if (-not $WhatIf) {
    ipconfig /flushdns | Out-Null
}

Write-Host "Wi-Fi '$($wlan.InterfaceAlias)' ($($wlan.ProfileName)):"
Write-Host "  IPv4 DNS: $($DnsServers -join ', ')"
Write-Host "  DoH template: $DohTemplate (manual encryption, AutoUpgrade)"
