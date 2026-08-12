#Requires -Version 5.1
<#
.SYNOPSIS
    Sets manual DNS and DoH on the active network connection.

.DESCRIPTION
    Finds the connected Wi-Fi or Ethernet adapter, registers DoH for the configured
    resolvers, assigns manual IPv4 DNS servers, and enables encrypted DNS (DoH)
    via AutoUpgrade. Requires elevation.

.PARAMETER ConnectionType
    Auto — pick the active connection with the default route (lowest metric wins).
    WiFi — active WLAN only.
    Ethernet — active 802.3 adapter only.
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'WiFi', 'Ethernet')]
    [string] $ConnectionType = 'Auto',

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

function Get-DefaultRouteMetric {
    param([int] $InterfaceIndex)

    $route = Get-NetRoute -InterfaceIndex $InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -ne '0.0.0.0' } |
        Sort-Object RouteMetric, InterfaceMetric |
        Select-Object -First 1

    if ($route) {
        return [int]$route.InterfaceMetric + [int]$route.RouteMetric
    }
    return [int]::MaxValue
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

    $interfaceIndex = if ($adapter) { $adapter.ifIndex } else { $null }

    [PSCustomObject]@{
        Kind           = 'WiFi'
        InterfaceAlias = if ($adapter) { $adapter.InterfaceAlias } else { $netshInterfaceName }
        InterfaceIndex = $interfaceIndex
        ProfileName    = $profileName
        RouteMetric    = if ($interfaceIndex) { Get-DefaultRouteMetric -InterfaceIndex $interfaceIndex } else { [int]::MaxValue }
    }
}

function Get-ConnectedEthernet {
    $candidates = @(Get-NetAdapter -Physical -ErrorAction Stop |
        Where-Object {
            $_.Status -eq 'Up' -and
            $_.MediaType -eq '802.3'
        })

    if ($candidates.Count -eq 0) {
        throw 'No active Ethernet connection (no Up adapter with MediaType 802.3).'
    }

    $scored = foreach ($adapter in $candidates) {
        [PSCustomObject]@{
            Kind           = 'Ethernet'
            InterfaceAlias = $adapter.InterfaceAlias
            InterfaceIndex = $adapter.ifIndex
            ProfileName    = $null
            RouteMetric    = Get-DefaultRouteMetric -InterfaceIndex $adapter.ifIndex
        }
    }

    $scored |
        Sort-Object RouteMetric, InterfaceIndex |
        Select-Object -First 1
}

function Get-ActiveConnection {
    param([string] $ConnectionType)

    switch ($ConnectionType) {
        'WiFi' {
            return Get-ConnectedWlan
        }
        'Ethernet' {
            return Get-ConnectedEthernet
        }
        'Auto' {
            $candidates = @()

            try { $candidates += Get-ConnectedWlan } catch { Write-Verbose $_.Exception.Message }
            try { $candidates += Get-ConnectedEthernet } catch { Write-Verbose $_.Exception.Message }

            if ($candidates.Count -eq 0) {
                throw 'No active Wi-Fi or Ethernet connection found.'
            }

            return $candidates |
                Sort-Object RouteMetric, InterfaceIndex |
                Select-Object -First 1
        }
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

$conn = Get-ActiveConnection -ConnectionType $ConnectionType
Write-Verbose "$($conn.Kind) interface: $($conn.InterfaceAlias)$(if ($conn.ProfileName) { ", profile: $($conn.ProfileName)" })"

foreach ($server in $DnsServers) {
    Set-DohServer -ServerAddress $server -DohTemplate $DohTemplate -WhatIf:$WhatIf
}

Set-InterfaceDns `
    -InterfaceAlias $conn.InterfaceAlias `
    -InterfaceIndex $conn.InterfaceIndex `
    -Servers $DnsServers `
    -WhatIf:$WhatIf

if (-not $WhatIf) {
    ipconfig /flushdns | Out-Null
}

$label = if ($conn.ProfileName) { "$($conn.InterfaceAlias) ($($conn.ProfileName))" } else { $conn.InterfaceAlias }
Write-Host "$($conn.Kind) '$label':"
Write-Host "  IPv4 DNS: $($DnsServers -join ', ')"
Write-Host "  DoH template: $DohTemplate (manual encryption, AutoUpgrade)"
