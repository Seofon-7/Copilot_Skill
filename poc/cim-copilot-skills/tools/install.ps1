<#
.SYNOPSIS
    One-time installer for the CIM Copilot Skills sync.

.DESCRIPTION
    1. Checks prerequisites (git, PowerShell version)
    2. Creates %USERPROFILE%\.cim-skills\ and writes config.json
    3. Copies the sync / uninstall scripts into %USERPROFILE%\.cim-skills\bin\
    4. Runs the first sync interactively (so Git Credential Manager can ask for a login)
    5. Registers a per-user scheduled task: at logon (+2 min) and daily (random delay 30 min)
       If the logon trigger is not allowed, falls back to a daily task + Startup folder shortcut.

    No administrator rights required. Keep this file ASCII-only.

.EXAMPLE
    .\install.ps1 -RepoUrl https://gitlab.example.local/cim/cim-copilot-skills.git -ReportDir \\fileserver\CIM\copilot-skills-status
#>
[CmdletBinding()]
param(
    [string]$RepoUrl,
    [ValidateSet('stable', 'beta')]
    [string]$Channel,
    [string]$ReportDir,
    [string]$ReportUrl,
    [string]$SkillsDir,
    # Daily run time (local time, HH:mm). A random delay of up to 30 minutes is added.
    [string]$DailyAt = '09:30',
    [switch]$NoSchedule,
    [switch]$SkipFirstSync
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$CimHome    = Join-Path $HOME '.cim-skills'
$BinDir     = Join-Path $CimHome 'bin'
$ConfigPath = Join-Path $CimHome 'config.json'
$TaskName   = 'CIM Copilot Skills Sync'
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
$IsWin      = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

function Write-Step { param([string]$Text) Write-Host "==> $Text" -ForegroundColor Cyan }

# 1. prerequisites ---------------------------------------------------------------
Write-Step 'Checking prerequisites'
if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'PowerShell 5.1 or later is required.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git was not found. Install Git for Windows first.' }
foreach ($f in @('cim-skills-sync.ps1', 'uninstall.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $f))) { throw "$f must be in the same folder as install.ps1." }
}

# 2. config -----------------------------------------------------------------------
Write-Step "Writing $ConfigPath"
[void][System.IO.Directory]::CreateDirectory($BinDir)
$config = [ordered]@{
    repoUrl       = ''
    channel       = 'stable'
    betaBranch    = 'main'
    pinnedVersion = ''
    skillsDir     = ''
    skillPrefix   = 'cim-'
    reportDir     = ''
    reportUrl     = ''
    reportUseWindowsAuth = $false
    selfUpdate    = $true
    keepBackups   = 5
    keepLogDays   = 14
}
if (Test-Path -LiteralPath $ConfigPath) {
    # keep existing values
    $existing = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    foreach ($p in $existing.PSObject.Properties) { $config[$p.Name] = $p.Value }
}
if ($RepoUrl)   { $config.repoUrl = $RepoUrl }
if ($Channel)   { $config.channel = $Channel }
if ($ReportDir) { $config.reportDir = $ReportDir }
if ($ReportUrl) { $config.reportUrl = $ReportUrl }
if ($SkillsDir) { $config.skillsDir = $SkillsDir }
if (-not $config.repoUrl) { throw 'Please pass -RepoUrl (the GitLab clone URL of the shared skills repository).' }
[System.IO.File]::WriteAllText($ConfigPath, ($config | ConvertTo-Json -Depth 5), $Utf8NoBom)

# 3. scripts ----------------------------------------------------------------------
Write-Step "Copying scripts to $BinDir"
foreach ($f in @('cim-skills-sync.ps1', 'uninstall.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination (Join-Path $BinDir $f) -Force
}
$SyncScript = Join-Path $BinDir 'cim-skills-sync.ps1'

# 4. first sync -------------------------------------------------------------------
if (-not $SkipFirstSync) {
    Write-Step 'Running the first sync (you may be asked to sign in to GitLab)'
    & $SyncScript -Interactive
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Warning "First sync finished with exit code $code. See $(Join-Path $CimHome 'logs') for details."
    }
}

# 5. schedule ---------------------------------------------------------------------
function Register-SyncSchedule {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Quiet' -f $SyncScript
    $user = '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME

    $action = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
    $daily = New-ScheduledTaskTrigger -Daily -At $DailyAt -RandomDelay (New-TimeSpan -Minutes 30)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $desc = 'Syncs the CIM team shared Copilot Agent Skills from GitLab into ~/.copilot/skills'

    try {
        $logon = New-ScheduledTaskTrigger -AtLogOn -User $user
        $logon.Delay = 'PT2M'     # give VPN / network time to come up
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $daily) -Settings $settings `
            -Principal $principal -Description $desc -Force | Out-Null
        return 'scheduled task (at logon + daily)'
    } catch {
        Write-Warning "Logon trigger not allowed ($($_.Exception.Message)). Using daily task + Startup shortcut instead."
    }

    $mode = @()
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $daily -Settings $settings `
            -Principal $principal -Description $desc -Force | Out-Null
        $mode += 'scheduled task (daily)'
    } catch {
        Write-Warning "Could not register a scheduled task: $($_.Exception.Message)"
    }
    $startup = [Environment]::GetFolderPath('Startup')
    $cmdPath = Join-Path $startup 'cim-skills-sync.cmd'
    $cmd = "@echo off`r`nstart `"`" /min `"$psExe`" $taskArgs`r`n"
    [System.IO.File]::WriteAllText($cmdPath, $cmd, (New-Object System.Text.ASCIIEncoding))
    $mode += "Startup shortcut ($cmdPath)"
    return ($mode -join ' + ')
}

$scheduleMode = 'not scheduled'
if ($NoSchedule) {
    $scheduleMode = 'skipped (-NoSchedule)'
} elseif (-not $IsWin) {
    $scheduleMode = 'skipped (not Windows; use cron / launchd to run cim-skills-sync.ps1)'
} else {
    Write-Step 'Registering automatic sync'
    $scheduleMode = Register-SyncSchedule
}

# 6. summary ----------------------------------------------------------------------
$skillsTarget = $config.skillsDir
if (-not $skillsTarget) { $skillsTarget = Join-Path (Join-Path $HOME '.copilot') 'skills' }
Write-Host ''
Write-Host 'CIM Copilot Skills installed.' -ForegroundColor Green
Write-Host "  Skills folder : $skillsTarget"
Write-Host "  Config        : $ConfigPath"
Write-Host "  Logs          : $(Join-Path $CimHome 'logs')"
Write-Host "  Auto sync     : $scheduleMode"
Write-Host "  Manual sync   : powershell -ExecutionPolicy Bypass -File `"$SyncScript`""
Write-Host '  Restart VS Code / Visual Studio (or open a new chat) so Copilot picks up the skills.'
