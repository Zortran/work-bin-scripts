#Requires -Version 5.1
<#
.SYNOPSIS
    Clone all repositories from a GitLab group and push them to another group/host.

.DESCRIPTION
    Lists non-archived repositories from the source group (including subgroups),
    clones each as a bare repository (git clone --bare), creates matching projects
    under the target group, keeps the source remote as "origin", adds the target
    remote as "new", then runs git push --mirror --push-option=ci.skip.

.PARAMETER SourceGroup
    Source GitLab group full path (e.g. myorg/team).

.PARAMETER TargetGroup
    Target GitLab group full path.

.PARAMETER SourceHost
    Optional source GitLab hostname (GITLAB_HOST). Defaults to glab configured host.

.PARAMETER TargetHost
    Optional target GitLab hostname. Defaults to SourceHost / glab configured host.

.PARAMETER DryRun
    Print actions without executing mutating commands.

.PARAMETER Archive
    After a successful push, mark the target repository as archived.

.PARAMETER Verbose
    Print detailed command lines and intermediate steps.

.EXAMPLE
    gclone_repos.cmd old/group new/group
    gclone_repos.cmd old/group new/group git.old.example git.new.example --dry --verbose
    gclone_repos.cmd old/group new/group --archive
#>
param(
    [string] $SourceGroup,
    [string] $TargetGroup,
    [string] $SourceHost = '',
    [string] $TargetHost = '',
    [switch] $DryRun,
    [switch] $Archive,
    [switch] $Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SourceGroup)) {
    throw 'SourceGroup is required. Usage: gclone_repos.cmd <SourceGroup> <TargetGroup> [SourceHost] [TargetHost] [--dry] [--verbose] [--archive]'
}
if ([string]::IsNullOrWhiteSpace($TargetGroup)) {
    throw 'TargetGroup is required. Usage: gclone_repos.cmd <SourceGroup> <TargetGroup> [SourceHost] [TargetHost] [--dry] [--verbose] [--archive]'
}
if ($Verbose) {
    $VerbosePreference = 'Continue'
}

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DRY', 'VERBOSE')]
        [string] $Level = 'INFO'
    )
    if ($Level -eq 'VERBOSE' -and $VerbosePreference -ne 'Continue') {
        return
    }
    $prefix = switch ($Level) {
        'DRY' { '[dry]' }
        'VERBOSE' { '[verbose]' }
        'WARN' { '[warn]' }
        'ERROR' { '[error]' }
        default { '[info]' }
    }
    Write-Host "$prefix $Message"
}

function Normalize-HostName {
    param([string] $HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        return ''
    }
    return ($HostName.Trim() -replace '^https?://', '').TrimEnd('/')
}

function Normalize-GroupPath {
    param([string] $Path)
    return ($Path.Trim() -replace '\\', '/' -replace '^/+|/+$', '')
}

function Get-DefaultGlabHost {
    $hostValue = (glab config get host 2>$null | Out-String).Trim()
    if (-not $hostValue) {
        throw 'Could not read default glab host. Pass SourceHost explicitly or configure glab.'
    }
    return (Normalize-HostName $hostValue)
}

function Get-GitProtocol {
    param([string] $HostName)
    $prev = $env:GITLAB_HOST
    try {
        if ($HostName) { $env:GITLAB_HOST = $HostName }
        $proto = (glab config get git_protocol 2>$null | Out-String).Trim()
        if ($proto -notin @('ssh', 'https', 'http')) {
            return 'ssh'
        }
        return $proto
    }
    finally {
        if ($null -eq $prev) { Remove-Item Env:GITLAB_HOST -ErrorAction SilentlyContinue }
        else { $env:GITLAB_HOST = $prev }
    }
}

function Invoke-External {
    param(
        [string] $FilePath,
        [string[]] $ArgumentList,
        [hashtable] $Environment = @{},
        [switch] $AllowFail,
        [switch] $Always
    )

    $displayEnv = @()
    foreach ($key in $Environment.Keys) {
        $displayEnv += "$key=$($Environment[$key])"
    }
    $display = if ($displayEnv.Count) {
        ($displayEnv -join ' ') + " $FilePath " + ($ArgumentList -join ' ')
    } else {
        "$FilePath " + ($ArgumentList -join ' ')
    }

    Write-Log $display -Level VERBOSE

    if ($DryRun -and -not $Always) {
        Write-Log $display -Level DRY
        return @{ ExitCode = 0; Output = @(); Display = $display; Stderr = '' }
    }

    $prevEnv = @{}
    foreach ($key in $Environment.Keys) {
        $prevEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
    }

    try {
        # Keep native stderr out of the success stream so JSON bodies stay clean.
        $stderrFile = [System.IO.Path]::GetTempFileName()
        try {
            $stdout = & $FilePath @ArgumentList 2>$stderrFile
            $succeeded = $?
            $code = $LASTEXITCODE
            if ($null -eq $code) {
                $code = if ($succeeded) { 0 } else { 1 }
            }

            $lines = @()
            if ($null -ne $stdout) {
                $lines = @($stdout | ForEach-Object { "$_" })
            }

            $stderrText = ''
            if (Test-Path -LiteralPath $stderrFile) {
                $stderrText = (Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue)
                if ($null -eq $stderrText) { $stderrText = '' }
                $stderrText = $stderrText.Trim()
            }

            if ($code -ne 0 -and -not $AllowFail) {
                $joined = ($lines -join [Environment]::NewLine)
                if ($stderrText) {
                    if ($joined) { $joined = "$joined`n$stderrText" } else { $joined = $stderrText }
                }
                throw "Command failed ($code): $display`n$joined"
            }
            return @{ ExitCode = [int]$code; Output = $lines; Display = $display; Stderr = $stderrText }
        }
        finally {
            Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $prevEnv[$key], 'Process')
        }
    }
}

function Invoke-GlabApi {
    param(
        [string] $HostName,
        [string[]] $ApiArgs,
        [switch] $AllowFail,
        [switch] $Always
    )
    $args = @('api')
    if ($HostName) {
        $args += @('--hostname', $HostName)
    }
    $args += $ApiArgs
    return Invoke-External -FilePath 'glab' -ArgumentList $args -AllowFail:$AllowFail -Always:$Always
}

function ConvertFrom-GlabApiOutput {
    param([object[]] $Output)

    if (-not $Output -or $Output.Count -eq 0) {
        return $null
    }

    $text = (@($Output | ForEach-Object { "$_" }) -join [Environment]::NewLine).Trim()
    if (-not $text) {
        return $null
    }

    # glab may mix stderr text with JSON when streams are merged; extract the payload.
    $match = [regex]::Match($text, '(?s)(\[[\s\S]*\]|\{[\s\S]*\})')
    if (-not $match.Success) {
        return $null
    }

    try {
        $obj = $match.Groups[1].Value | ConvertFrom-Json
    }
    catch {
        return $null
    }

    # API error bodies like {"message":"404 Project Not Found"} have no id.
    if ($obj -is [System.Management.Automation.PSObject]) {
        $names = @($obj.PSObject.Properties.Name)
        if (($names -contains 'message') -and ($names -notcontains 'id')) {
            return $null
        }
    }

    return $obj
}

function Get-ProjectByPath {
    param(
        [string] $HostName,
        [string] $ProjectPath
    )
    $encoded = [uri]::EscapeDataString($ProjectPath)
    $result = Invoke-GlabApi -HostName $HostName -ApiArgs @("projects/$encoded") -AllowFail -Always
    if ($result.ExitCode -ne 0) {
        return $null
    }
    return (ConvertFrom-GlabApiOutput -Output $result.Output)
}

function Get-GroupByPath {
    param(
        [string] $HostName,
        [string] $GroupPath
    )
    $encoded = [uri]::EscapeDataString($GroupPath)
    $result = Invoke-GlabApi -HostName $HostName -ApiArgs @("groups/$encoded") -AllowFail -Always
    if ($result.ExitCode -ne 0) {
        return $null
    }
    return (ConvertFrom-GlabApiOutput -Output $result.Output)
}

function Ensure-GroupPath {
    param(
        [string] $HostName,
        [string] $GroupPath
    )

    $existing = Get-GroupByPath -HostName $HostName -GroupPath $GroupPath
    if ($existing) {
        Write-Log "Group exists: $GroupPath" -Level VERBOSE
        return $existing
    }

    $parts = $GroupPath -split '/'
    $current = ''
    $parentId = $null

    foreach ($part in $parts) {
        $current = if ($current) { "$current/$part" } else { $part }
        $group = Get-GroupByPath -HostName $HostName -GroupPath $current
        if ($group) {
            $parentId = $group.id
            continue
        }

        Write-Log "Creating group: $current"
        $apiArgs = @(
            'groups',
            '--method', 'POST',
            '-f', "name=$part",
            '-f', "path=$part"
        )
        if ($null -ne $parentId) {
            $apiArgs += @('-f', "parent_id=$parentId")
        }

        if ($DryRun) {
            Write-Log "glab api $($apiArgs -join ' ')  (GITLAB_HOST=$HostName)" -Level DRY
            $parentId = 0
            continue
        }

        $created = Invoke-GlabApi -HostName $HostName -ApiArgs $apiArgs
        $obj = ConvertFrom-GlabApiOutput -Output $created.Output
        if (-not $obj) {
            throw "Failed to create group '$current' on $HostName"
        }
        $parentId = $obj.id
    }

    return (Get-GroupByPath -HostName $HostName -GroupPath $GroupPath)
}

function Ensure-TargetProject {
    param(
        [string] $HostName,
        [string] $ProjectPath
    )

    $existing = Get-ProjectByPath -HostName $HostName -ProjectPath $ProjectPath
    if ($existing) {
        Write-Log "Project already exists: $ProjectPath"
        return $existing
    }

    $slash = $ProjectPath.LastIndexOf('/')
    if ($slash -lt 0) {
        throw "Target project path must include a group namespace: $ProjectPath"
    }
    $namespacePath = $ProjectPath.Substring(0, $slash)
    $projectName = $ProjectPath.Substring($slash + 1)

    $namespace = Ensure-GroupPath -HostName $HostName -GroupPath $namespacePath
    if (-not $DryRun -and (-not $namespace -or -not $namespace.id)) {
        throw "Target namespace not found after ensure: $namespacePath"
    }

    Write-Log "Creating project: $ProjectPath"
    $apiArgs = @(
        'projects',
        '--method', 'POST',
        '-f', "name=$projectName",
        '-f', "path=$projectName"
    )
    if (-not $DryRun) {
        $apiArgs += @('-f', "namespace_id=$($namespace.id)")
    }

    if ($DryRun) {
        Write-Log "glab api $($apiArgs -join ' ') -f namespace_id=<id of $namespacePath>  (--hostname $HostName)" -Level DRY
        return [pscustomobject]@{
            path_with_namespace = $ProjectPath
            ssh_url_to_repo     = "git@${HostName}:${ProjectPath}.git"
            http_url_to_repo    = "https://${HostName}/${ProjectPath}.git"
        }
    }

    $created = Invoke-GlabApi -HostName $HostName -ApiArgs $apiArgs
    $obj = ConvertFrom-GlabApiOutput -Output $created.Output
    if (-not $obj) {
        # Fallback: project may exist or response parsing failed — reload by path.
        $obj = Get-ProjectByPath -HostName $HostName -ProjectPath $ProjectPath
    }
    if (-not $obj) {
        $detail = ($created.Output -join [Environment]::NewLine)
        if ($created.Stderr) { $detail = "$detail`n$($created.Stderr)" }
        throw "Failed to create project '$ProjectPath' on $HostName`: $detail"
    }
    return $obj
}

function Get-RemoteUrl {
    param(
        [object] $Project,
        [string] $HostName
    )
    $proto = Get-GitProtocol -HostName $HostName
    if ($proto -eq 'ssh' -and $Project.ssh_url_to_repo) {
        return [string]$Project.ssh_url_to_repo
    }
    if ($Project.http_url_to_repo) {
        return [string]$Project.http_url_to_repo
    }
    if ($Project.ssh_url_to_repo) {
        return [string]$Project.ssh_url_to_repo
    }
    throw "No clone URL available for $($Project.path_with_namespace)"
}

function Get-SourceProjects {
    param(
        [string] $HostName,
        [string] $GroupPath
    )

    $encoded = [uri]::EscapeDataString($GroupPath)
    $endpoint = "groups/$encoded/projects?archived=false&include_subgroups=true&with_shared=true&per_page=100"
    $result = Invoke-GlabApi -HostName $HostName -ApiArgs @(
        $endpoint,
        '--paginate'
    ) -Always -AllowFail

    if ($result.ExitCode -ne 0) {
        $joined = ($result.Output -join [Environment]::NewLine)
        if ($result.Stderr) {
            if ($joined) { $joined = "$joined`n$($result.Stderr)" } else { $joined = $result.Stderr }
        }
        throw "Cannot list projects for source group '$GroupPath' on $HostName`: $joined"
    }

    $parsed = ConvertFrom-GlabApiOutput -Output $result.Output
    if (-not $parsed) {
        return @()
    }

    return @(
        @($parsed) |
            Where-Object {
                $path = Normalize-GroupPath ([string]$_.path_with_namespace)
                $path -and ($path -eq $GroupPath -or $path.StartsWith("$GroupPath/"))
            } |
            Sort-Object { Normalize-GroupPath ([string]$_.path_with_namespace) }
    )
}

function Get-LocalRepoDir {
    param([string] $NamespacePath)
    return (Join-Path (Get-Location) ($NamespacePath -replace '/', [IO.Path]::DirectorySeparatorChar))
}

function Test-BareRepo {
    param([string] $RepoDir)
    # Bare repo has HEAD + config at the root (no .git directory).
    return (
        (Test-Path -LiteralPath (Join-Path $RepoDir 'HEAD')) -and
        (Test-Path -LiteralPath (Join-Path $RepoDir 'config'))
    )
}

function Clone-BareRepo {
    param(
        [string] $SourceUrl,
        [string] $RepoDir
    )

    if ($DryRun) {
        Write-Log "git clone --bare $SourceUrl `"$RepoDir`"" -Level DRY
        return
    }

    if (Test-BareRepo -RepoDir $RepoDir) {
        Write-Log "Bare clone already exists, fetching updates: $RepoDir" -Level VERBOSE
        Invoke-External -FilePath 'git' -ArgumentList @(
            '-C', $RepoDir, 'fetch', '--prune', 'origin', '+refs/*:refs/*'
        ) | Out-Null
        return
    }

    if (Test-Path -LiteralPath $RepoDir) {
        throw "Path exists but is not a bare git repository: $RepoDir"
    }

    $parent = Split-Path -Parent $RepoDir
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-Log "Cloning bare: $SourceUrl"
    Invoke-External -FilePath 'git' -ArgumentList @(
        'clone', '--bare', $SourceUrl, $RepoDir
    ) | Out-Null
}

function Set-RepoRemotes {
    param(
        [string] $RepoDir,
        [string] $NewRemoteUrl
    )

    if ($DryRun) {
        Write-Log "git -C `"$RepoDir`" remote add new $NewRemoteUrl" -Level DRY
        return
    }

    Push-Location -LiteralPath $RepoDir
    try {
        $remotes = @(& git remote 2>$null)
        if ($remotes -notcontains 'origin') {
            throw "No 'origin' remote found in $RepoDir"
        }

        if ($remotes -contains 'new') {
            Write-Log "Remote 'new' already exists in $RepoDir — updating URL" -Level WARN
            Invoke-External -FilePath 'git' -ArgumentList @('remote', 'set-url', 'new', $NewRemoteUrl) | Out-Null
        }
        else {
            Invoke-External -FilePath 'git' -ArgumentList @('remote', 'add', 'new', $NewRemoteUrl) | Out-Null
        }
    }
    finally {
        Pop-Location
    }
}

function Push-MirrorRepo {
    param([string] $RepoDir)

    if ($DryRun) {
        Write-Log "git -C `"$RepoDir`" push --mirror new --push-option=ci.skip" -Level DRY
        return
    }

    Push-Location -LiteralPath $RepoDir
    try {
        Write-Log 'Pushing with --mirror'
        Invoke-External -FilePath 'git' -ArgumentList @(
            'push', '--mirror', 'new', '--push-option=ci.skip'
        ) | Out-Null
    }
    finally {
        Pop-Location
    }
}

function Set-ProjectArchived {
    param(
        [string] $HostName,
        [object] $Project,
        [string] $ProjectPath
    )

    $projectId = $null
    if ($Project -and $Project.id) {
        $projectId = [string]$Project.id
    }
    if (-not $projectId) {
        $loaded = Get-ProjectByPath -HostName $HostName -ProjectPath $ProjectPath
        if ($loaded -and $loaded.id) {
            $projectId = [string]$loaded.id
        }
    }
    if (-not $projectId) {
        $projectId = [uri]::EscapeDataString($ProjectPath)
    }

    if ($DryRun) {
        Write-Log "glab api --hostname $HostName --method POST projects/$projectId/archive" -Level DRY
        return
    }

    Write-Log "Archiving target project: $ProjectPath"
    $result = Invoke-GlabApi -HostName $HostName -ApiArgs @(
        "--method", "POST",
        "projects/$projectId/archive"
    )
    $obj = ConvertFrom-GlabApiOutput -Output $result.Output
    if ($obj -and ($obj.PSObject.Properties.Name -contains 'archived') -and -not [bool]$obj.archived) {
        throw "Archive request completed but project is not archived: $ProjectPath"
    }
}

# --- main -------------------------------------------------------------------

if (-not (Get-Command glab -ErrorAction SilentlyContinue)) {
    throw 'glab is not available in PATH'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is not available in PATH'
}

$SourceGroup = Normalize-GroupPath $SourceGroup
$TargetGroup = Normalize-GroupPath $TargetGroup
if (-not $SourceGroup) { throw 'SourceGroup is required' }
if (-not $TargetGroup) { throw 'TargetGroup is required' }

$SourceHost = Normalize-HostName $SourceHost
$TargetHost = Normalize-HostName $TargetHost
if (-not $SourceHost) { $SourceHost = Get-DefaultGlabHost }
if (-not $TargetHost) { $TargetHost = $SourceHost }

Write-Log "Source group : $SourceGroup @$SourceHost"
Write-Log "Target group : $TargetGroup @$TargetHost"
if ($Archive) { Write-Log 'Target projects will be archived after push' }
if ($DryRun) { Write-Log 'Dry run enabled — no changes will be made' -Level DRY }

Write-Log "Listing repositories in $SourceGroup"
$sourceProjects = @(Get-SourceProjects -HostName $SourceHost -GroupPath $SourceGroup)

if ($sourceProjects.Count -eq 0) {
    Write-Log "No repositories found for group '$SourceGroup'" -Level WARN
    exit 0
}

Write-Log "Found $($sourceProjects.Count) repositor$(if ($sourceProjects.Count -eq 1) { 'y' } else { 'ies' })"

$failed = @()
foreach ($sourceProject in $sourceProjects) {
    $sourcePath = Normalize-GroupPath ([string]$sourceProject.path_with_namespace)
    $repoDir = Get-LocalRepoDir -NamespacePath $sourcePath
    try {
        $suffix = if ($sourcePath.Length -gt $SourceGroup.Length) {
            $sourcePath.Substring($SourceGroup.Length).TrimStart('/')
        } else {
            ''
        }
        if (-not $suffix) {
            Write-Log "Skipping group path without project segment: $sourcePath" -Level WARN
            continue
        }

        $targetPath = "$TargetGroup/$suffix"
        Write-Log "=== $sourcePath -> $targetPath ==="

        $sourceUrl = Get-RemoteUrl -Project $sourceProject -HostName $SourceHost
        Write-Log "Source URL: $sourceUrl" -Level VERBOSE
        Clone-BareRepo -SourceUrl $sourceUrl -RepoDir $repoDir

        $project = Ensure-TargetProject -HostName $TargetHost -ProjectPath $targetPath
        $newRemoteUrl = Get-RemoteUrl -Project $project -HostName $TargetHost
        Write-Log "Remote new: $newRemoteUrl" -Level VERBOSE

        if (-not $DryRun -and -not (Test-BareRepo -RepoDir $repoDir)) {
            throw "Bare repository not found: $repoDir"
        }

        Set-RepoRemotes -RepoDir $repoDir -NewRemoteUrl $newRemoteUrl
        Push-MirrorRepo -RepoDir $repoDir
        if ($Archive) {
            Set-ProjectArchived -HostName $TargetHost -Project $project -ProjectPath $targetPath
        }
        Write-Log "Done: $targetPath"
    }
    catch {
        $failed += [pscustomobject]@{ Repo = $sourcePath; Error = $_.Exception.Message }
        Write-Log "Failed: $sourcePath — $($_.Exception.Message)" -Level ERROR
    }
}

if ($failed.Count -gt 0) {
    Write-Log "$($failed.Count) repositor$(if ($failed.Count -eq 1) { 'y' } else { 'ies' }) failed:" -Level ERROR
    foreach ($item in $failed) {
        Write-Log "  $($item.Repo): $($item.Error)" -Level ERROR
    }
    exit 1
}

Write-Log 'All repositories processed successfully'
