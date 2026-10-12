<#
.SYNOPSIS
    Removes the CIM Copilot Skills sync: managed skills, scheduled task,
    Startup shortcut and %USERPROFILE%\.cim-skills. Personal skills are kept.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$HOME\.cim-skills\bin\uninstall.ps1"
.EXAMPLE
    .\uninstall.ps1 -KeepBackups -Force
#>
[CmdletBinding()]
param(
    # Keep %USERPROFILE%\.cim-skills\backup (copies of locally edited skills).
    [switch]$KeepBackups,
    # Do not ask for confirmation.
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$CimHome    = Join-Path $HOME '.cim-skills'
$ConfigPath = Join-Path $CimHome 'config.json'
$StatePath  = Join-Path $CimHome 'state.json'
$TaskName   = 'CIM Copilot Skills Sync'
$IsWin      = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json)
}

if (-not $Force) {
    $answer = Read-Host 'Remove CIM shared skills and the automatic sync from this computer? (y/N)'
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; exit 0 }
}

Set-Location -LiteralPath $HOME
$config = Read-Json $ConfigPath
$state  = Read-Json $StatePath

# 1. managed skills (only the ones listed in state.json)
if ($state -and $state.PSObject.Properties['skills'] -and $state.skills) {
    $skillsDir = $state.skillsDir
    foreach ($p in $state.skills.PSObject.Properties) {
        $dir = Join-Path $skillsDir $p.Name
        if (Test-Path -LiteralPath $dir) {
            Remove-Item -LiteralPath $dir -Recurse -Force
            Write-Host "Removed skill $($p.Name)"
        }
    }
}

# 2. scheduled task + Startup shortcut
if ($IsWin) {
    try {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Removed scheduled task '$TaskName'"
        }
    } catch { Write-Warning "Could not remove the scheduled task: $($_.Exception.Message)" }
    $cmdPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'cim-skills-sync.cmd'
    if (Test-Path -LiteralPath $cmdPath) { Remove-Item -LiteralPath $cmdPath -Force; Write-Host 'Removed Startup shortcut' }
}

# 3. tell the dashboard this machine was uninstalled on purpose
if ($config -and $config.PSObject.Properties['reportDir'] -and $config.reportDir) {
    try {
        $name = ('{0}@{1}' -f [Environment]::UserName, [Environment]::MachineName) -replace '[\\/:*?"<>|\s]', '_'
        $report = [ordered]@{
            schema = 1; user = [Environment]::UserName; domain = $env:USERDOMAIN; host = [Environment]::MachineName
            status = 'uninstalled'; message = 'Removed by uninstall.ps1'; reportedAt = (Get-Date).ToString('o')
        }
        [System.IO.File]::WriteAllText((Join-Path $config.reportDir "$name.json"), ($report | ConvertTo-Json),
            (New-Object System.Text.UTF8Encoding($false)))
    } catch { Write-Warning "Could not write the uninstall heartbeat: $($_.Exception.Message)" }
}

# 4. local files
if (Test-Path -LiteralPath $CimHome) {
    foreach ($item in Get-ChildItem -LiteralPath $CimHome -Force) {
        if ($KeepBackups -and $item.Name -eq 'backup') { continue }
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
    if (-not $KeepBackups) { Remove-Item -LiteralPath $CimHome -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host 'CIM Copilot Skills sync removed.' -ForegroundColor Green
