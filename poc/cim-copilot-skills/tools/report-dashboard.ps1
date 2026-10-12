<#
.SYNOPSIS
    Builds an HTML dashboard (and optional CSV) showing which version of the
    CIM shared skills every engineer has, and who is out of date.

.DESCRIPTION
    Reads the heartbeat JSON files written by cim-skills-sync.ps1 (or by
    heartbeat_server.py) from -ReportDir, compares them with the latest
    release tag in GitLab and with the team roster (-MembersCsv).

    Status (worst first):
      Not installed  - in the roster but no heartbeat at all
      Sync failed    - last run could not reach GitLab or hit an error
      Outdated       - running an older release
      Stale          - no heartbeat for more than -StaleDays days
      Pinned         - deliberately pinned to a version
      Uninstalled    - removed with uninstall.ps1
      Up to date

    Keep this file ASCII-only (Windows PowerShell 5.1).

.EXAMPLE
    .\report-dashboard.ps1 -ReportDir \\fileserver\CIM\copilot-skills-status `
        -RepoUrl https://gitlab.example.local/cim/cim-copilot-skills.git `
        -MembersCsv \\fileserver\CIM\copilot-skills-status\_members.csv `
        -OutHtml \\fileserver\CIM\copilot-skills-status\_dashboard.html -OutCsv .\skills-status.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReportDir,
    # Used to look up release tags (git ls-remote). Optional if -LatestVersion is given.
    [string]$RepoUrl,
    [string]$LatestVersion,
    # CSV with columns: account,name,team  (account = Windows user name)
    [string]$MembersCsv,
    [string]$OutHtml = '.\skills-dashboard.html',
    [string]$OutCsv,
    [int]$StaleDays = 3
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    if ($p.Value -is [string] -and $p.Value -eq '') { return $Default }
    return $p.Value
}

function ConvertTo-LocalTime {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToLocalTime() }
    try {
        return ([DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)).LocalDateTime
    } catch { return $null }
}

function HtmlEncode([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }

# 1. release tags -----------------------------------------------------------------
$releases = @()
if ($RepoUrl) {
    $env:GIT_TERMINAL_PROMPT = '0'
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $lines = @(& git ls-remote --tags --refs $RepoUrl 2>&1 | ForEach-Object { "$_" })
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "git ls-remote failed: $($lines -join ' | ')" }
    foreach ($l in $lines) {
        if ($l -match 'refs/tags/(v(\d+)\.(\d+)\.(\d+))$') {
            $releases += [pscustomobject]@{
                Tag = $Matches[1]
                Ver = New-Object System.Version ([int]$Matches[2]), ([int]$Matches[3]), ([int]$Matches[4])
            }
        }
    }
    $releases = @($releases | Sort-Object Ver)
}
if (-not $LatestVersion) {
    if ($releases.Count -eq 0) { throw 'Cannot determine the latest version: pass -RepoUrl or -LatestVersion.' }
    $LatestVersion = $releases[-1].Tag
}
$releaseTags = @($releases | ForEach-Object { $_.Tag })

function Get-VersionsBehind([string]$Version) {
    if (-not $Version -or $releaseTags.Count -eq 0) { return '' }
    $i = [array]::IndexOf($releaseTags, $Version)
    $j = [array]::IndexOf($releaseTags, $LatestVersion)
    if ($i -lt 0 -or $j -lt 0) { return '?' }
    return [string]($j - $i)
}

# 2. roster -----------------------------------------------------------------------
$members = @{}
if ($MembersCsv) {
    foreach ($m in Import-Csv -LiteralPath $MembersCsv -Encoding UTF8) {
        $acct = ([string]$m.account).Trim().ToLowerInvariant()
        if ($acct) { $members[$acct] = $m }
    }
}

# 3. heartbeats -------------------------------------------------------------------
$now = Get-Date
$rows = New-Object System.Collections.Generic.List[object]
$seen = @{}
$rank = @{ 'Not installed' = 0; 'Sync failed' = 1; 'Outdated' = 2; 'Stale' = 3; 'Pinned' = 4; 'Uninstalled' = 5; 'Up to date' = 6 }

foreach ($file in Get-ChildItem -LiteralPath $ReportDir -Filter '*.json' -File) {
    try {
        $r = [System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
    } catch {
        Write-Warning "Skipping unreadable file $($file.Name)"
        continue
    }
    $user = ([string](Get-Prop $r 'user' '')).ToLowerInvariant()
    if (-not $user) { continue }
    $seen[$user] = $true
    $version  = [string](Get-Prop $r 'version' '')
    $status   = [string](Get-Prop $r 'status' '')
    $reported = ConvertTo-LocalTime (Get-Prop $r 'reportedAt')
    $lastOk   = ConvertTo-LocalTime (Get-Prop $r 'lastCheckAt')
    $pinned   = [bool](Get-Prop $r 'pinned' $false)
    $modified = @(Get-Prop $r 'localModified' @())

    if ($status -eq 'uninstalled')                           { $state = 'Uninstalled' }
    elseif ($status -ne 'ok')                                { $state = 'Sync failed' }
    elseif ($version -ne $LatestVersion -and -not $pinned)   { $state = 'Outdated' }
    elseif (-not $reported -or ($now - $reported).TotalDays -gt $StaleDays) { $state = 'Stale' }
    elseif ($version -ne $LatestVersion -and $pinned)        { $state = 'Pinned' }
    else                                                     { $state = 'Up to date' }

    $ide = Get-Prop $r 'ide'
    $vs = @(Get-Prop $ide 'visualStudio' @()) -join '; '
    $member = $null
    if ($members.ContainsKey($user)) { $member = $members[$user] }

    $rows.Add([pscustomobject]@{
        State         = $state
        Account       = [string](Get-Prop $r 'user' '')
        Name          = $(if ($member) { [string]$member.name } else { '(not in roster)' })
        Team          = $(if ($member) { [string]$member.team } else { '' })
        Host          = [string](Get-Prop $r 'host' '')
        Version       = $version
        Behind        = Get-VersionsBehind $version
        Channel       = [string](Get-Prop $r 'channel' '')
        LastHeartbeat = $(if ($reported) { $reported.ToString('yyyy-MM-dd HH:mm') } else { '' })
        LastSuccess   = $(if ($lastOk) { $lastOk.ToString('yyyy-MM-dd HH:mm') } else { '' })
        LocalEdits    = ($modified -join ', ')
        VSCode        = [string](Get-Prop $ide 'vscode' '')
        CopilotChat   = [string](Get-Prop $ide 'copilotChat' '')
        VisualStudio  = $vs
        Message       = [string](Get-Prop $r 'message' '')
    })
}

foreach ($acct in $members.Keys) {
    if ($seen.ContainsKey($acct)) { continue }
    $m = $members[$acct]
    $rows.Add([pscustomobject]@{
        State = 'Not installed'; Account = [string]$m.account; Name = [string]$m.name; Team = [string]$m.team
        Host = ''; Version = ''; Behind = ''; Channel = ''; LastHeartbeat = ''; LastSuccess = ''; LocalEdits = ''
        VSCode = ''; CopilotChat = ''; VisualStudio = ''; Message = 'No heartbeat received'
    })
}

$sorted = @($rows | Sort-Object @{ Expression = { $rank[$_.State] } }, Team, Name, Host)

# 4. summary ----------------------------------------------------------------------
$counts = [ordered]@{}
foreach ($k in ($rank.Keys | Sort-Object { $rank[$_] })) { $counts[$k] = @($sorted | Where-Object { $_.State -eq $k }).Count }
$people = @($sorted | Where-Object { $_.State -ne 'Uninstalled' } | ForEach-Object { $_.Account.ToLowerInvariant() } | Sort-Object -Unique)
$peopleOk = @($people | Where-Object {
        $a = $_
        $mine = @($sorted | Where-Object { $_.Account.ToLowerInvariant() -eq $a -and $_.State -ne 'Uninstalled' })
        @($mine | Where-Object { $_.State -ne 'Up to date' -and $_.State -ne 'Pinned' }).Count -eq 0
    })
$pct = 0
if ($people.Count -gt 0) { $pct = [math]::Round(100.0 * $peopleOk.Count / $people.Count, 0) }

# 5. HTML -------------------------------------------------------------------------
$css = @'
:root { --bg:#f7f7f5; --card:#fff; --text:#1f2328; --muted:#656d76; --line:#d8dee4;
  --bad:#cf222e; --warn:#bf8700; --ok:#1a7f37; --info:#0969da; --grey:#6e7781; }
* { box-sizing: border-box; }
body { margin:0; padding:24px 16px; background:var(--bg); color:var(--text);
  font-family: "Segoe UI", "Microsoft JhengHei", system-ui, sans-serif; font-size:14px; }
h1 { font-size:20px; margin:0 0 4px; }
.meta { color:var(--muted); margin-bottom:16px; }
.cards { display:flex; flex-wrap:wrap; gap:12px; margin-bottom:20px; }
.card { background:var(--card); border:1px solid var(--line); border-radius:8px; padding:12px 16px; min-width:130px; }
.card .n { font-size:24px; font-weight:600; }
.card .l { color:var(--muted); font-size:12px; }
.wrap { overflow-x:auto; background:var(--card); border:1px solid var(--line); border-radius:8px; }
table { border-collapse:collapse; width:100%; }
th, td { padding:8px 10px; border-bottom:1px solid var(--line); text-align:left; white-space:nowrap; vertical-align:top; }
th { background:#f0f2f4; font-weight:600; position:sticky; top:0; }
td.msg { white-space:normal; min-width:220px; color:var(--muted); }
.badge { display:inline-block; padding:2px 8px; border-radius:999px; color:#fff; font-size:12px; }
.s0, .s1 { background:var(--bad); } .s2 { background:var(--warn); } .s3 { background:var(--grey); }
.s4 { background:var(--info); } .s5 { background:#8c959f; } .s6 { background:var(--ok); }
.edit { color:var(--warn); font-weight:600; }
'@

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!DOCTYPE html><html><head><meta charset="utf-8">')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
[void]$sb.AppendLine('<title>CIM Skills Status</title><style>' + $css + '</style></head><body>')
[void]$sb.AppendLine('<h1>CIM Copilot Skills - version status</h1>')
[void]$sb.AppendLine(('<div class="meta">Latest release: <b>{0}</b> &middot; Generated {1} &middot; Stale after {2} days</div>' -f
        (HtmlEncode $LatestVersion), $now.ToString('yyyy-MM-dd HH:mm'), $StaleDays))
[void]$sb.AppendLine('<div class="cards">')
[void]$sb.AppendLine(('<div class="card"><div class="n">{0}%</div><div class="l">People fully up to date ({1}/{2})</div></div>' -f $pct, $peopleOk.Count, $people.Count))
foreach ($k in $counts.Keys) {
    [void]$sb.AppendLine(('<div class="card"><div class="n">{0}</div><div class="l"><span class="badge s{1}">{2}</span></div></div>' -f $counts[$k], $rank[$k], (HtmlEncode $k)))
}
[void]$sb.AppendLine('</div><div class="wrap"><table><thead><tr>')
$cols = @('State', 'Name', 'Account', 'Team', 'Host', 'Version', 'Behind', 'Channel', 'LastHeartbeat', 'LastSuccess', 'LocalEdits', 'VSCode', 'CopilotChat', 'VisualStudio', 'Message')
foreach ($c in $cols) { [void]$sb.Append('<th>' + $c + '</th>') }
[void]$sb.AppendLine('</tr></thead><tbody>')
foreach ($r in $sorted) {
    [void]$sb.Append('<tr>')
    foreach ($c in $cols) {
        $v = [string]$r.$c
        switch ($c) {
            'State'      { [void]$sb.Append(('<td><span class="badge s{0}">{1}</span></td>' -f $rank[$v], (HtmlEncode $v))) }
            'LocalEdits' { [void]$sb.Append(('<td class="edit">{0}</td>' -f (HtmlEncode $v))) }
            'Message'    { [void]$sb.Append(('<td class="msg">{0}</td>' -f (HtmlEncode $v))) }
            default      { [void]$sb.Append(('<td>{0}</td>' -f (HtmlEncode $v))) }
        }
    }
    [void]$sb.AppendLine('</tr>')
}
[void]$sb.AppendLine('</tbody></table></div></body></html>')

$utf8 = New-Object System.Text.UTF8Encoding($false)
$htmlPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutHtml)
[System.IO.File]::WriteAllText($htmlPath, $sb.ToString(), $utf8)
Write-Host "Dashboard written to $htmlPath"

if ($OutCsv) {
    # UTF-8 with BOM so Excel shows Chinese names correctly
    $lines = $sorted | Select-Object $cols | ConvertTo-Csv -NoTypeInformation
    $csvPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutCsv)
    [System.IO.File]::WriteAllLines($csvPath, [string[]]$lines, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "CSV written to $csvPath"
}

Write-Host ('Latest {0}: {1}/{2} people fully up to date; outdated={3}, failed={4}, not installed={5}' -f
    $LatestVersion, $peopleOk.Count, $people.Count, $counts['Outdated'], $counts['Sync failed'], $counts['Not installed'])
