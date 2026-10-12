<#
.SYNOPSIS
    Sync the CIM team's shared Copilot Agent Skills from the internal GitLab
    repository into the user-level skills folder (~/.copilot/skills), which is
    read by both Visual Studio and VS Code.

.DESCRIPTION
    - Pulls the latest release tag (stable channel), a branch (beta channel),
      or a pinned version.
    - Copies every skills/<prefix>* folder into the user skills folder.
    - Only touches folders it manages (tracked in state.json). Personal skills
      without the team prefix are never touched.
    - Detects local edits to managed skills, backs them up, then restores the
      official version.
    - Removes managed skills that were deleted or renamed upstream.
    - Writes a heartbeat (version / status / IDE versions) to a shared folder
      and/or an HTTP endpoint so the team can see who is out of date.

    Works on Windows PowerShell 5.1 and PowerShell 7+.
    Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.

    Exit codes: 0 = OK, 1 = error, 2 = could not reach GitLab (kept current version)

.EXAMPLE
    .\cim-skills-sync.ps1                  # normal run (used by the scheduled task)
.EXAMPLE
    .\cim-skills-sync.ps1 -Version v1.2.0  # one-off install of a specific version
.EXAMPLE
    .\cim-skills-sync.ps1 -Force           # reinstall even if already up to date
#>
[CmdletBinding()]
param(
    # Install this tag once (e.g. v1.2.0). For a permanent pin use pinnedVersion in config.json.
    [string]$Version,
    # Overrides the channel in config.json for this run.
    [ValidateSet('stable', 'beta')]
    [string]$Channel,
    [string]$ConfigPath,
    # Reinstall all managed skills even if nothing changed.
    [switch]$Force,
    # Do not send a heartbeat.
    [switch]$NoReport,
    # Allow git / Git Credential Manager to prompt for credentials (first install only).
    [switch]$Interactive,
    # No console output (log file only). Used by the scheduled task.
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.0.0'
$CimHome    = Join-Path $HOME '.cim-skills'
if (-not $ConfigPath) { $ConfigPath = Join-Path $CimHome 'config.json' }
$RepoDir    = Join-Path $CimHome 'repo'
$StatePath  = Join-Path $CimHome 'state.json'
$LogDir     = Join-Path $CimHome 'logs'
$BackupRoot = Join-Path $CimHome 'backup'
$StagingDir = Join-Path $CimHome 'staging'
$BinDir     = Join-Path $CimHome 'bin'
$LockPath   = Join-Path $CimHome 'sync.lock'
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
$script:LogFile = $null

# ---------------------------------------------------------------- helpers ---

function Write-SyncLog {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:LogFile) {
        try { [System.IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, $Utf8NoBom) } catch { }
    }
    if (-not $Quiet) {
        switch ($Level) {
            'WARN'  { Write-Host $line -ForegroundColor Yellow }
            'ERROR' { Write-Host $line -ForegroundColor Red }
            default { Write-Host $line }
        }
    }
}

# Read a property from a PSCustomObject / hashtable; empty strings count as "not set".
function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $value = $null
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { $value = $Object[$Name] }
    } else {
        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) { $value = $p.Value }
    }
    if ($null -eq $value) { return $Default }
    if ($value -is [string] -and $value -eq '') { return $Default }
    return $value
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path)   # detects UTF-8 BOM automatically
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param([string]$Path, $Object)
    $json = $Object | ConvertTo-Json -Depth 8
    $tmp = '{0}.{1}.tmp' -f $Path, ([guid]::NewGuid().ToString('N').Substring(0, 8))
    [System.IO.File]::WriteAllText($tmp, $json, $Utf8NoBom)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# PowerShell 7 turns ISO date strings into [datetime] when reading JSON; 5.1 does not.
function Format-Date {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToString('o') }
    return [string]$Value
}

# Run git without letting stderr progress output turn into terminating errors (PS 5.1 issue).
function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments, [switch]$AllowFail)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($code -ne 0 -and -not $AllowFail) {
        throw ('git {0} failed (exit {1}): {2}' -f ($Arguments -join ' '), $code, ($output -join ' | '))
    }
    return [pscustomobject]@{ Code = $code; Output = $output }
}

function Get-GitValue {
    param([string[]]$Arguments)
    $r = Invoke-Git -Arguments $Arguments
    return ($r.Output | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1).Trim()
}

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

# Stable content hash of a folder: relative paths + file SHA256, sorted ordinally.
function Get-FolderHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $root = Get-FullPath $Path
    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($file in [System.IO.Directory]::GetFiles($root, '*', [System.IO.SearchOption]::AllDirectories)) {
        $rel = $file.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        $entries.Add($rel + ':' + $hash)
    }
    $arr = $entries.ToArray()
    [System.Array]::Sort($arr, [System.StringComparer]::Ordinal)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($arr -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

# Copy a folder including hidden files (Copy-Item may skip them).
function Copy-Folder {
    param([string]$Source, [string]$Destination)
    $src = Get-FullPath $Source
    $dst = Get-FullPath $Destination
    [void][System.IO.Directory]::CreateDirectory($dst)
    foreach ($dir in [System.IO.Directory]::GetDirectories($src, '*', [System.IO.SearchOption]::AllDirectories)) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $dst $dir.Substring($src.Length).TrimStart('\', '/')))
    }
    foreach ($file in [System.IO.Directory]::GetFiles($src, '*', [System.IO.SearchOption]::AllDirectories)) {
        [System.IO.File]::Copy($file, (Join-Path $dst $file.Substring($src.Length).TrimStart('\', '/')), $true)
    }
}

function Remove-Folder {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Get-SafeName {
    param([string]$Name)
    return ($Name -replace '[\\/:*?"<>|\s]', '_')
}

# Best effort: which IDE / Copilot versions are installed (for the dashboard).
function Get-IdeInfo {
    $info = [ordered]@{ vscode = $null; copilotChat = $null; visualStudio = @() }

    try {
        $roots = @()
        if ($env:LOCALAPPDATA) { $roots += Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code' }
        if ($env:ProgramFiles) { $roots += Join-Path $env:ProgramFiles 'Microsoft VS Code' }
        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            $pkg = Join-Path $root 'resources\app\package.json'
            if (-not (Test-Path -LiteralPath $pkg)) {
                # newer layouts may keep resources in a versioned sub folder
                $found = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { Join-Path $_.FullName 'resources\app\package.json' } |
                    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
                if ($found) { $pkg = $found }
            }
            if (Test-Path -LiteralPath $pkg) { $info.vscode = [string](Read-JsonFile $pkg).version; break }
        }
        if (-not $info.vscode -and (Get-Command code -ErrorAction SilentlyContinue)) {
            $first = @(& code --version 2>$null) | Select-Object -First 1
            if ($first) { $info.vscode = [string]$first }
        }
    } catch { }

    try {
        $extDir = Join-Path (Join-Path $HOME '.vscode') 'extensions'
        if (Test-Path -LiteralPath $extDir) {
            $best = $null
            foreach ($d in Get-ChildItem -LiteralPath $extDir -Directory -Filter 'github.copilot-chat-*' -ErrorAction SilentlyContinue) {
                if ($d.Name -match '^github\.copilot-chat-(\d+\.\d+\.\d+)') {
                    $v = [version]$Matches[1]
                    if ($null -eq $best -or $v -gt $best) { $best = $v }
                }
            }
            if ($best) { $info.copilotChat = $best.ToString() }
        }
    } catch { }

    try {
        $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        if ($pf86) {
            $vswhere = Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe'
            if (Test-Path -LiteralPath $vswhere) {
                $json = (& $vswhere -all -prerelease -format json -utf8) -join ''
                $list = @()
                foreach ($vs in @($json | ConvertFrom-Json)) {
                    $ver = Get-Prop (Get-Prop $vs 'catalog') 'productDisplayVersion' (Get-Prop $vs 'installationVersion')
                    $list += ('{0} ({1})' -f (Get-Prop $vs 'displayName' 'Visual Studio'), $ver)
                }
                $info.visualStudio = $list
            }
        }
    } catch { }

    return $info
}

function Send-Heartbeat {
    param($Config, $Report)
    $reportDir = Get-Prop $Config 'reportDir'
    $reportUrl = Get-Prop $Config 'reportUrl'
    if (-not $reportDir -and -not $reportUrl) { Write-SyncLog 'No reportDir/reportUrl configured; heartbeat skipped.'; return }

    if ($reportDir) {
        try {
            if (-not (Test-Path -LiteralPath $reportDir)) { throw "Report folder not reachable: $reportDir" }
            $file = Join-Path $reportDir ((Get-SafeName ('{0}@{1}' -f $Report.user, $Report.host)) + '.json')
            Write-JsonFile -Path $file -Object $Report
            Write-SyncLog "Heartbeat written to $file"
        } catch {
            Write-SyncLog "Heartbeat to folder failed: $($_.Exception.Message)" 'WARN'
        }
    }
    if ($reportUrl) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $body = [System.Text.Encoding]::UTF8.GetBytes(($Report | ConvertTo-Json -Depth 8))
            $irm = @{ Uri = $reportUrl; Method = 'Post'; Body = $body; ContentType = 'application/json; charset=utf-8'; TimeoutSec = 10 }
            # Windows integrated auth only when the receiver needs it (and preferably over https)
            if ([bool](Get-Prop $Config 'reportUseWindowsAuth' $false)) { $irm.UseDefaultCredentials = $true }
            Invoke-RestMethod @irm | Out-Null
            Write-SyncLog "Heartbeat posted to $reportUrl"
        } catch {
            Write-SyncLog "Heartbeat to URL failed: $($_.Exception.Message)" 'WARN'
        }
    }
}

# Map of skill name -> hash from state.json (works for PSCustomObject and hashtable).
function Get-ManagedSkills {
    param($State)
    $map = @{}
    $skills = Get-Prop $State 'skills'
    if ($null -eq $skills) { return $map }
    if ($skills -is [System.Collections.IDictionary]) {
        foreach ($k in $skills.Keys) { $map[[string]$k] = [string]$skills[$k] }
    } else {
        foreach ($p in $skills.PSObject.Properties) { $map[$p.Name] = [string]$p.Value }
    }
    return $map
}

function Resolve-Target {
    param([string]$Pinned, [string]$ChannelName, [string]$BetaBranch)
    if ($Pinned) {
        $r = Invoke-Git -Arguments @('-C', $RepoDir, 'rev-parse', '--verify', '--quiet', "refs/tags/$Pinned^{commit}") -AllowFail
        if ($r.Code -ne 0) { throw "Version '$Pinned' was not found in the repository tags." }
        return [pscustomobject]@{ Label = $Pinned; Commit = $r.Output[0].Trim(); Pinned = $true }
    }
    if ($ChannelName -eq 'beta') {
        $sha = Get-GitValue @('-C', $RepoDir, 'rev-parse', '--verify', "refs/remotes/origin/$BetaBranch^{commit}")
        return [pscustomobject]@{ Label = ('{0}@{1}' -f $BetaBranch, $sha.Substring(0, 8)); Commit = $sha; Pinned = $false }
    }
    $bestTag = $null
    $bestVer = $null
    foreach ($t in (Invoke-Git -Arguments @('-C', $RepoDir, 'tag', '--list', 'v*')).Output) {
        $t = $t.Trim()
        if ($t -match '^v(\d+)\.(\d+)\.(\d+)$') {
            $v = New-Object System.Version ([int]$Matches[1]), ([int]$Matches[2]), ([int]$Matches[3])
            if ($null -eq $bestVer -or $v -gt $bestVer) { $bestVer = $v; $bestTag = $t }
        }
    }
    if (-not $bestTag) { throw 'No release tag (vX.Y.Z) found in the repository.' }
    $sha = Get-GitValue @('-C', $RepoDir, 'rev-parse', "refs/tags/$bestTag^{commit}")
    return [pscustomobject]@{ Label = $bestTag; Commit = $sha; Pinned = $false }
}

function Remove-OldItems {
    param($Config)
    try {
        $keepBackups = [int](Get-Prop $Config 'keepBackups' 5)
        if (Test-Path -LiteralPath $BackupRoot) {
            Get-ChildItem -LiteralPath $BackupRoot -Directory | Sort-Object Name -Descending |
                Select-Object -Skip $keepBackups | ForEach-Object { Remove-Folder $_.FullName }
        }
        $keepLogDays = [int](Get-Prop $Config 'keepLogDays' 14)
        $limit = (Get-Date).AddDays(-$keepLogDays)
        Get-ChildItem -LiteralPath $LogDir -File -Filter 'sync-*.log' |
            Where-Object { $_.LastWriteTime -lt $limit } | Remove-Item -Force
    } catch {
        Write-SyncLog "Cleanup failed: $($_.Exception.Message)" 'WARN'
    }
}

# ------------------------------------------------------------------- main ---

function Invoke-Sync {
    $config = Read-JsonFile $ConfigPath
    if ($null -eq $config) { throw "Config not found: $ConfigPath (run install.ps1 first)." }

    $repoUrl    = Get-Prop $config 'repoUrl'
    if (-not $repoUrl) { throw 'repoUrl is not set in config.json.' }
    $prefix     = Get-Prop $config 'skillPrefix' 'cim-'
    $skillsDir  = Get-Prop $config 'skillsDir' (Join-Path (Join-Path $HOME '.copilot') 'skills')
    $chan       = $Channel
    if (-not $chan) { $chan = Get-Prop $config 'channel' 'stable' }
    $betaBranch = Get-Prop $config 'betaBranch' 'main'
    $pinned     = $Version
    if (-not $pinned) { $pinned = Get-Prop $config 'pinnedVersion' }

    if (-not $Interactive) {
        # Never hang a hidden scheduled task on a credential prompt.
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GCM_INTERACTIVE = 'never'
    }

    $state   = Read-JsonFile $StatePath
    $managed = Get-ManagedSkills $state
    $result  = [ordered]@{ status = 'ok'; message = ''; localModified = @(); changes = @() }
    $exitCode = 0

    # 1. fetch ---------------------------------------------------------------
    $fetched = $false
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is not installed or not on PATH.' }
        if (-not (Test-Path -LiteralPath (Join-Path $RepoDir '.git'))) {
            Remove-Folder $RepoDir
            Write-SyncLog "Cloning $repoUrl"
            Invoke-Git -Arguments @('clone', '--quiet', '--no-checkout', $repoUrl, $RepoDir) | Out-Null
        } else {
            $currentUrl = Get-GitValue @('-C', $RepoDir, 'remote', 'get-url', 'origin')
            if ($currentUrl -ne $repoUrl) { Invoke-Git -Arguments @('-C', $RepoDir, 'remote', 'set-url', 'origin', $repoUrl) | Out-Null }
        }
        Invoke-Git -Arguments @('-C', $RepoDir, 'fetch', '--quiet', '--tags', '--prune', '--prune-tags', '--force', 'origin') | Out-Null
        $fetched = $true
    } catch {
        $result.status = 'fetch_failed'
        $result.message = $_.Exception.Message
        $exitCode = 2
        Write-SyncLog "Could not update from GitLab, keeping the installed version. $($_.Exception.Message)" 'WARN'
    }

    # 2. resolve + install ------------------------------------------------------
    $newState = $null
    if ($fetched) {
        $target = Resolve-Target -Pinned $pinned -ChannelName $chan -BetaBranch $betaBranch
        Write-SyncLog ('Target: {0} ({1}) channel={2}{3}' -f $target.Label, $target.Commit.Substring(0, 8), $chan, $(if ($target.Pinned) { ' [pinned]' } else { '' }))

        Invoke-Git -Arguments @('-C', $RepoDir, '-c', 'advice.detachedHead=false', 'checkout', '--quiet', '--force', $target.Commit) | Out-Null
        Invoke-Git -Arguments @('-C', $RepoDir, 'clean', '-fdxq') | Out-Null

        $srcRoot = Join-Path $RepoDir 'skills'
        if (-not (Test-Path -LiteralPath $srcRoot)) { throw "No 'skills' folder in repository at $($target.Label)." }
        $sources = @{}
        foreach ($d in Get-ChildItem -LiteralPath $srcRoot -Directory) {
            if (-not $d.Name.StartsWith($prefix)) { Write-SyncLog "Skipped '$($d.Name)': name must start with '$prefix'." 'WARN'; continue }
            if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'SKILL.md'))) { Write-SyncLog "Skipped '$($d.Name)': no SKILL.md." 'WARN'; continue }
            $sources[$d.Name] = $d.FullName
        }

        [void][System.IO.Directory]::CreateDirectory($skillsDir)
        $backupDir = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
        $hashes = [ordered]@{}

        # 2a. managed skills that no longer exist upstream (deleted / renamed)
        foreach ($name in @($managed.Keys)) {
            if ($sources.ContainsKey($name)) { continue }
            $dst = Join-Path $skillsDir $name
            if (Test-Path -LiteralPath $dst) {
                if ((Get-FolderHash $dst) -ne $managed[$name]) {
                    Copy-Folder $dst (Join-Path $backupDir $name)
                    $result.localModified += $name
                }
                Remove-Folder $dst
            }
            $result.changes += "removed $name"
            Write-SyncLog "Removed '$name' (no longer in the shared repository)."
        }

        # 2b. add / update / repair
        foreach ($name in ($sources.Keys | Sort-Object)) {
            $dst = Join-Path $skillsDir $name
            $srcHash = Get-FolderHash $sources[$name]
            $dstHash = Get-FolderHash $dst
            if ($null -ne $dstHash -and $dstHash -eq $srcHash -and -not $Force) {
                $hashes[$name] = $dstHash
                continue
            }
            if ($null -ne $dstHash) {
                $isManaged = $managed.ContainsKey($name)
                if (-not $isManaged -or $dstHash -ne $managed[$name]) {
                    # edited locally, or an unmanaged folder with the same name: keep a copy
                    Copy-Folder $dst (Join-Path $backupDir $name)
                    $result.localModified += $name
                    Write-SyncLog "'$name' was modified locally; backed up to $backupDir" 'WARN'
                }
            }
            $stage = Join-Path $StagingDir $name
            Remove-Folder $stage
            Copy-Folder $sources[$name] $stage
            Remove-Folder $dst
            try {
                Move-Item -LiteralPath $stage -Destination $dst
            } catch {
                Copy-Folder $stage $dst      # different volume: fall back to copy
                Remove-Folder $stage
            }
            $hashes[$name] = Get-FolderHash $dst
            if ($null -eq $dstHash) { $verb = 'added' } else { $verb = 'updated' }
            $result.changes += "$verb $name"
            Write-SyncLog "$verb '$name'"
        }

        $now = (Get-Date).ToString('o')
        $installedAt = Format-Date (Get-Prop $state 'installedAt')
        if ($result.changes.Count -gt 0 -or -not $installedAt) { $installedAt = $now }
        $newState = [ordered]@{
            schema        = 1
            version       = $target.Label
            commit        = $target.Commit
            channel       = $chan
            pinned        = [bool]$target.Pinned
            skillsDir     = $skillsDir
            skills        = $hashes
            installedAt   = $installedAt
            lastCheckAt   = $now
            scriptVersion = $ScriptVersion
        }
        Write-JsonFile -Path $StatePath -Object $newState

        if ($result.changes.Count -eq 0) {
            Write-SyncLog "Already up to date ($($target.Label))."
        } else {
            Write-SyncLog ("Synced to {0}: {1}" -f $target.Label, ($result.changes -join ', '))
        }

        # 3. self-update the installed scripts ------------------------------------
        if ([bool](Get-Prop $config 'selfUpdate' $true) -and $PSCommandPath) {
            $runningFromBin = (Get-FullPath (Split-Path -Parent $PSCommandPath)) -eq (Get-FullPath $BinDir)
            if ($runningFromBin) {
                foreach ($f in @('cim-skills-sync.ps1', 'uninstall.ps1')) {
                    $src = Join-Path (Join-Path $RepoDir 'tools') $f
                    $dst = Join-Path $BinDir $f
                    if ((Test-Path -LiteralPath $src) -and (-not (Test-Path -LiteralPath $dst) -or
                            (Get-FileHash -LiteralPath $src).Hash -ne (Get-FileHash -LiteralPath $dst).Hash)) {
                        Copy-Item -LiteralPath $src -Destination $dst -Force
                        Write-SyncLog "Self-update: $f replaced with the version from $($target.Label)."
                    }
                }
            }
        }
    }

    Remove-OldItems $config

    # 4. heartbeat ------------------------------------------------------------
    if (-not $NoReport) {
        $s = $newState
        if ($null -eq $s) { $s = $state }   # fetch failed: report what is installed now
        $installed = @()
        $skillMap = Get-ManagedSkills $s
        if ($skillMap.Count -gt 0) { $installed = @($skillMap.Keys | Sort-Object) }
        $report = [ordered]@{
            schema          = 1
            user            = [Environment]::UserName
            domain          = $env:USERDOMAIN
            host            = [Environment]::MachineName
            status          = $result.status
            message         = $result.message
            version         = Get-Prop $s 'version'
            commit          = Get-Prop $s 'commit'
            channel         = Get-Prop $s 'channel'
            pinned          = [bool](Get-Prop $s 'pinned' $false)
            installedSkills = $installed
            localModified   = @($result.localModified)
            changes         = @($result.changes)
            installedAt     = Format-Date (Get-Prop $s 'installedAt')
            lastCheckAt     = Format-Date (Get-Prop $s 'lastCheckAt')
            reportedAt      = (Get-Date).ToString('o')
            scriptVersion   = $ScriptVersion
            psVersion       = $PSVersionTable.PSVersion.ToString()
            os              = [Environment]::OSVersion.VersionString
            ide             = Get-IdeInfo
        }
        Send-Heartbeat -Config $config -Report $report
    }

    return $exitCode
}

# --------------------------------------------------------------- entrypoint ---

[void][System.IO.Directory]::CreateDirectory($CimHome)
[void][System.IO.Directory]::CreateDirectory($LogDir)
$script:LogFile = Join-Path $LogDir ('sync-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))

$lock = $null
try {
    $lock = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
    Write-SyncLog 'Another sync is already running; exiting.' 'WARN'
    exit 0
}

$code = 1
try {
    Write-SyncLog "=== cim-skills-sync $ScriptVersion start ==="
    $code = Invoke-Sync
} catch {
    Write-SyncLog "Sync failed: $($_.Exception.Message)" 'ERROR'
    $code = 1
    # still try to tell the dashboard that this machine has a problem
    if (-not $NoReport) {
        try {
            $cfg = Read-JsonFile $ConfigPath
            $st = Read-JsonFile $StatePath
            Send-Heartbeat -Config $cfg -Report ([ordered]@{
                schema = 1; user = [Environment]::UserName; domain = $env:USERDOMAIN; host = [Environment]::MachineName
                status = 'error'; message = $_.Exception.Message
                version = Get-Prop $st 'version'; commit = Get-Prop $st 'commit'; channel = Get-Prop $st 'channel'
                pinned = [bool](Get-Prop $st 'pinned' $false)
                installedAt = Format-Date (Get-Prop $st 'installedAt'); lastCheckAt = Format-Date (Get-Prop $st 'lastCheckAt')
                reportedAt = (Get-Date).ToString('o'); scriptVersion = $ScriptVersion
            })
        } catch { }
    }
} finally {
    Write-SyncLog "=== end (exit $code) ==="
    if ($lock) { $lock.Dispose() }
}
exit $code
