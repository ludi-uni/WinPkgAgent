function Test-WpaWingetAvailable { param([string]$Executable='winget'); $null -ne (Resolve-WpaManagerExecutable -Manager winget) }
function ConvertFrom-WpaWingetExport {
    param([Parameter(Mandatory)][string]$Json)
    try { $data = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $sourcesProperty = $data.PSObject.Properties['Sources']
    if ($null -eq $sourcesProperty) { return $null }
    $packages = @($sourcesProperty.Value | ForEach-Object { Get-WpaPropertyValue $_ 'Packages' @() })
    if ($packages.Count -eq 0) { Write-Output -NoEnumerate ([object[]]@()); return }
    $result = foreach($p in $packages) {
        if ([string]::IsNullOrWhiteSpace($p.PackageIdentifier)) { return $null }
        $version=Get-WpaPropertyValue $p 'Version';$source=Get-WpaPropertyValue $p 'Source'
        [pscustomobject]@{ Id=[string]$p.PackageIdentifier; Version=if($version){[string]$version}else{$null}; Manager='winget'; Source=if($source){[string]$source}else{$null} }
    }
    @($result)
}
function ConvertFrom-WpaWingetFallback {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text -notmatch '(?m)(Name\s+Version|\u540d\u524d\s+\u30d0\u30fc\u30b8\u30e7\u30f3)') { return $null }
    $rows = @()
    foreach($line in ($Text -split "`r?`n")) {
        if ($line -match '^(?<id>[A-Za-z0-9_.+-]+)\s+(?<version>\S+)$' -and $Matches.id -notmatch '^(?:Name|\u540d\u524d)$') { $rows += [pscustomobject]@{Id=$Matches.id;Version=$Matches.version;Manager='winget';Source=$null} }
    }
    if ($rows.Count -eq 0) { return $null }; $rows
}
function ConvertFrom-WpaWingetList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $lines = @($Text -split "`r?`n")
    $headerIndex = -1
    $starts = $null
    foreach ($labels in @(
        @('Name','Id','Version','Available','Source'),
        @('名前','ID','バージョン','利用可能','ソース')
    )) {
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            $candidateStarts = @()
            $cursor = 0
            $matched = $true
            foreach ($label in $labels) {
                $position = $line.IndexOf($label, $cursor, [StringComparison]::Ordinal)
                if ($position -lt 0) { $matched = $false; break }
                $candidateStarts += $position
                $cursor = $position + $label.Length
            }
            if ($matched) { $headerIndex = $index; $starts = $candidateStarts; break }
        }
        if ($headerIndex -ge 0) { break }
    }
    if ($headerIndex -lt 0) { return $null }
    $rows = [System.Collections.Generic.List[object]]::new()
    for ($index = $headerIndex + 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim() -match '^-{3,}(?:\s+-{3,})*$') { continue }
        $columns = @($line.Trim() -split '\s{2,}')
        if ($columns.Count -eq 2) {
            $tail = @($columns[1] -split '\s+')
            if ($tail.Count -lt 2) { return $null }
            $columns = @($columns[0], (($tail[0..($tail.Count - 2)] -join ' ')), $tail[-1])
        }
        if ($columns.Count -lt 3 -or $columns.Count -gt 5) { return $null }
        $name = $columns[0]
        $id = $columns[1]
        $version = $columns[2]
        $available = $null
        $source = $null
        switch ($columns.Count) {
            4 {
                if ($columns[3] -match '^(?i:winget|msstore)$') { $source = $columns[3] } else { $available = $columns[3] }
            }
            5 {
                $available = $columns[3]
                $source = $columns[4]
            }
        }
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) { return $null }
        $rows.Add([pscustomobject]@{
            DisplayName = $name
            Id = $id
            Version = $version
            AvailableVersion = if ($available) { $available } else { $null }
            Source = if ($source) { $source } else { $null }
        })
    }
    @($rows)
}
function Get-WpaWingetUnmanagedObservations {
    [CmdletBinding()]
    param([string[]]$KnownIds = @(), [int]$TimeoutSeconds = 30)
    $executable = Resolve-WpaManagerExecutable -Manager winget
    if (-not $executable) {
        return [pscustomobject]@{ status='failed'; observations=@(); warning='winget list unavailable or malformed' }
    }
    $result = Invoke-WpaProcess -FilePath $executable -Arguments @('list','--disable-interactivity') -TimeoutSeconds $TimeoutSeconds -NoTruncateOutput
    if ($result.TimedOut -or $result.ExitCode -ne 0) {
        return [pscustomobject]@{ status='failed'; observations=@(); warning='winget list unavailable or malformed' }
    }
    $rows = ConvertFrom-WpaWingetList -Text $result.StdOut
    if ($null -eq $rows) {
        return [pscustomobject]@{ status='failed'; observations=@(); warning='winget list unavailable or malformed' }
    }
    $known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($knownId in @($KnownIds)) { if ($knownId) { $known.Add([string]$knownId) | Out-Null } }
    $observations = foreach ($row in @($rows)) {
        if ($known.Contains([string]$row.Id)) { continue }
        $managerCandidate = ([string]$row.Id -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$') -and -not [string]::IsNullOrWhiteSpace([string]$row.Source)
        [pscustomobject]@{
            displayName = [string]$row.DisplayName
            observedId = [string]$row.Id
            installedVersion = [string]$row.Version
            availableVersion = $row.AvailableVersion
            source = $row.Source
            actionability = if ($managerCandidate) { 'manager-candidate' } else { 'manual-mapping' }
            reasonCode = if ($managerCandidate) { 'UNMANAGED_MANAGER_CANDIDATE' } else { 'UNMANAGED_ID_REQUIRES_MAPPING' }
            reviewStatus = 'pending'
            detectedBy = 'winget-list'
        }
    }
    [pscustomobject]@{ status='success'; observations=@($observations); warning=$null }
}
function ConvertFrom-WpaWingetUpgrade {
    param([string]$Text)
    if($Text -notmatch '(?mi)^\s*(Name\s{2,}Id\s{2,}Version\s{2,}Available|\u540d\u524d\s{2,}ID\s{2,}\u30d0\u30fc\u30b8\u30e7\u30f3\s{2,}\u5229\u7528\u53ef\u80fd)'){return $null}
    $items=@()
    foreach($line in ($Text -split "`r?`n")){
        $columns=@($line.Trim() -split '\s{2,}')
        if($columns.Count -ge 4 -and $columns[1] -match '^[A-Za-z0-9][A-Za-z0-9._+-]{0,199}$' -and $columns[2] -notmatch '^(Version|\u30d0\u30fc\u30b8\u30e7\u30f3)$'){$items+=[pscustomobject]@{Id=$columns[1];AvailableVersion=$columns[3]}}
    }
    [pscustomobject]@{Valid=$true;Items=@($items)}
}
function Get-WpaWingetInventory {
    param([string]$Executable='winget',[int]$TimeoutSeconds=30)
    $Executable = Resolve-WpaManagerExecutable -Manager winget
    if(-not $Executable) { return [pscustomobject]@{manager='winget';version=$null;status='failed';timedOut=$false;Packages=@();warning='winget executable unavailable';Available=$false;Success=$false;Raw=$null} }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('wpa-winget-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
      $r = Invoke-WpaProcess -FilePath $Executable -Arguments @('export','--include-versions','--output',$tmp) -TimeoutSeconds $TimeoutSeconds
      $json = if((Test-Path -LiteralPath $tmp) -and ((Get-Item $tmp).Length -le 4MB)){ [System.IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8) } else { '' }
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    $packages = if(-not $r.TimedOut -and $r.ExitCode -eq 0){ ConvertFrom-WpaWingetExport $json } else {$null}
    $v=Invoke-WpaProcess -FilePath $Executable -Arguments @('--version') -TimeoutSeconds $TimeoutSeconds;$managerVersion=if($v.ExitCode -eq 0){$v.StdOut.Trim()}else{$null}
    $u=Invoke-WpaProcess -FilePath $Executable -Arguments @('upgrade','--disable-interactivity') -TimeoutSeconds $TimeoutSeconds; $updates=if($u.ExitCode -eq 0){ConvertFrom-WpaWingetUpgrade $u.StdOut}else{$null}; if($packages -and $null -ne $updates -and $updates.Valid){foreach($p in $packages){$m=$updates.Items|Where-Object Id -eq $p.Id|Select-Object -First 1;if($m){$p|Add-Member NoteProperty AvailableVersion $m.AvailableVersion -Force}}}
    if($null -eq $packages -and -not $r.TimedOut){ $packages = ConvertFrom-WpaWingetFallback $r.StdOut }
    $status=if($null -eq $packages){'failed'}elseif($null -eq $updates -or $null -eq $managerVersion){'partial'}else{'success'}
    [pscustomobject]@{ manager='winget'; version=$managerVersion; status=$status; timedOut=($r.TimedOut -or $u.TimedOut -or $v.TimedOut); Packages=@($packages | Where-Object {$null -ne $_} | ForEach-Object {[pscustomobject]@{manager='winget';id=$_.Id;displayName=$_.Id;installedVersion=$_.Version;availableVersion=(Get-WpaPropertyValue $_ 'AvailableVersion');source=$_.Source;scope=$null;metadata=@{detectedBy='winget-export'}}}); warning=if($null -eq $packages){'winget inventory unavailable or malformed'}elseif($null -eq $updates -or $null -eq $managerVersion){'winget version or update output unavailable or unrecognized'}else{$null}; Available=(Test-WpaWingetAvailable $Executable); Success=($null -ne $packages); Raw=$r }
}
function Install-WpaWingetPackage { [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30); if($Id -notmatch '^[A-Za-z0-9_.-]+$'){throw 'invalid id'}; $Executable=Resolve-WpaManagerExecutable -Manager winget; if(-not $Executable){throw 'winget executable unavailable'}; $a=@('install','--id',$Id,'--exact','--disable-interactivity','--accept-source-agreements','--accept-package-agreements'); if($Version){$a+=@('--version',$Version)}; if($Source){$a+=@('--source',$Source)}; if($PSCmdlet.ShouldProcess("winget/$Id",'install')){Invoke-WpaProcess -FilePath $Executable -Arguments $a -TimeoutSeconds $TimeoutSeconds} }
function Update-WpaWingetPackage { [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30); $Executable=Resolve-WpaManagerExecutable -Manager winget; if(-not $Executable){throw 'winget executable unavailable'}; $a=@('upgrade','--id',$Id,'--exact','--disable-interactivity','--accept-source-agreements','--accept-package-agreements'); if($Version){$a+=@('--version',$Version)}; if($Source){$a+=@('--source',$Source)}; if($PSCmdlet.ShouldProcess("winget/$Id",'upgrade')){Invoke-WpaProcess -FilePath $Executable -Arguments $a -TimeoutSeconds $TimeoutSeconds} }
