function Test-WpaScoopAvailable { $null -ne (Resolve-WpaManagerExecutable -Manager scoop) }
function ConvertFrom-WpaScoopExport {
    param([Parameter(Mandatory)][string]$Json)
    try { $data = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $appsProperty = $data.PSObject.Properties['apps']
    $apps = if($null -ne $appsProperty){ $appsProperty.Value } else { $null }
    $items = if($data -is [System.Collections.IEnumerable] -and $data -isnot [string]){@($data)} elseif($null -ne $appsProperty){@($apps)} else {@($data)}
    if($null -ne $appsProperty -and @($apps).Count -eq 0){ Write-Output -InputObject ([object[]]@()) -NoEnumerate; return }
    $result = foreach($p in $items) {
        $id = Get-WpaPropertyValue $p 'name'; if([string]::IsNullOrWhiteSpace($id)){ $id=Get-WpaPropertyValue $p 'Name' }
        if([string]::IsNullOrWhiteSpace($id)){ return $null }
        $version=Get-WpaPropertyValue $p 'version';$bucket=Get-WpaPropertyValue $p 'bucket';[pscustomobject]@{Id=[string]$id;Version=if($version){[string]$version}else{$null};Manager='scoop';Source=if($bucket){[string]$bucket}else{$null}}
    }
    @($result)
}
function ConvertFrom-WpaScoopFallback {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $lines=@($Text -split "`r?`n" | ForEach-Object {$_.Trim()} | Where-Object {$_})
    if($lines.Count -lt 2 -or $lines[0] -notmatch '^(?:Name\s+Version|\u540d\u524d\s+\u30d0\u30fc\u30b8\u30e7\u30f3)$'){return $null}
    $rows=@()
    for($index=1;$index -lt $lines.Count;$index++) {
        if($lines[$index] -notmatch '^(?<id>[A-Za-z0-9_.+-]+)\s+(?<version>\S+)$'){return $null}
        $rows += [pscustomobject]@{Id=$Matches.id;Version=$Matches.version;Manager='scoop';Source=$null}
    }
    return $rows
}
function ConvertFrom-WpaScoopVersion {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Text)
    $lines=@($Text -split "`r?`n" | ForEach-Object {$_.Trim()} | Where-Object {$_})
    if($lines.Count -eq 1 -and $lines[0] -match '^v?(?<version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)$'){
        return $Matches.version
    }
    if($lines.Count -lt 2 -or $lines[0] -cne 'Current Scoop version:' -or $lines[1] -notmatch '^v(?<version>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\s+-\s+Released at \d{4}-\d{2}-\d{2}$'){
        return $null
    }
    $version=$Matches.version
    for($index=2;$index -lt $lines.Count;$index+=2) {
        if(($index+1) -ge $lines.Count -or $lines[$index] -notmatch "^'[^'`r`n]{1,128}' bucket:$" -or $lines[$index+1] -notmatch '^[0-9a-fA-F]{7,40}\s+\S.*$'){
            return $null
        }
    }
    return $version
}
function ConvertFrom-WpaScoopStatus {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Text)
    $lines=@($Text -split "`r?`n")
    $nonEmptyLines=@($lines | ForEach-Object {$_.Trim()} | Where-Object {$_})
    if($nonEmptyLines.Count -eq 1 -and $nonEmptyLines[0] -ceq 'Everything is ok!'){
        return [pscustomobject]@{Valid=$true;Items=@()}
    }
    if($nonEmptyLines.Count -eq 0){return $null}
    $lines=$nonEmptyLines

    $currentHeaderIndex=-1
    $currentStarts=$null
    $line=$lines[0]
    $starts=@()
    $cursor=0
    $matched=$true
    foreach($label in @('Name','Installed Version','Latest Version','Missing Dependencies','Info')) {
        $position=$line.IndexOf($label,$cursor,[StringComparison]::Ordinal)
        if($position -lt 0){$matched=$false;break}
        $starts+=$position
        $cursor=$position+$label.Length
    }
    if($matched -and $starts[0] -eq 0 -and [string]::IsNullOrWhiteSpace($line.Substring($cursor))){
        $currentHeaderIndex=0
        $currentStarts=$starts
    }
    if($currentHeaderIndex -ge 0) {
        $items=@()
        for($index=$currentHeaderIndex+1;$index -lt $lines.Count;$index++) {
            $line=$lines[$index]
            if([string]::IsNullOrWhiteSpace($line) -or $line.Trim() -match '^-+(?:\s+-+)+$'){continue}
            if($line.Length -le $currentStarts[2]){return $null}
            $id=$line.Substring(0,$currentStarts[1]).Trim()
            $installedEnd=[Math]::Min($line.Length,$currentStarts[2])
            $installed=$line.Substring($currentStarts[1],$installedEnd-$currentStarts[1]).Trim()
            $latest=if($line.Length -gt $currentStarts[2]){
                $latestEnd=[Math]::Min($line.Length,$currentStarts[3])
                $line.Substring($currentStarts[2],$latestEnd-$currentStarts[2]).Trim()
            }else{''}
            if($id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,199}$' -or [string]::IsNullOrWhiteSpace($installed)){return $null}
            $items+=[pscustomobject]@{Id=$id;AvailableVersion=if($latest){$latest}else{$null}}
        }
        if($items.Count -eq 0){return $null}
        return [pscustomobject]@{Valid=$true;Items=@($items)}
    }

    $legacyHeaderIndex=if($lines[0] -match '^(?:Name\s{2,}Installed\s{2,}Latest|\u540d\u524d\s{2,}\u30a4\u30f3\u30b9\u30c8\u30fc\u30eb\u6e08\u307f\s{2,}\u6700\u65b0)$'){0}else{-1}
    if($legacyHeaderIndex -lt 0){return $null}
    $items=@()
    for($index=$legacyHeaderIndex+1;$index -lt $lines.Count;$index++) {
        $line=$lines[$index]
        if([string]::IsNullOrWhiteSpace($line) -or $line.Trim() -match '^-+(?:\s+-+)+$'){continue}
        $columns=@($line.Trim() -split '\s{2,}')
        if($columns.Count -lt 3 -or $columns[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,199}$'){return $null}
        $items+=[pscustomobject]@{Id=$columns[0];AvailableVersion=$columns[2]}
    }
    if($items.Count -eq 0){return $null}
    return [pscustomobject]@{Valid=$true;Items=@($items)}
}
function Get-WpaScoopInventory {
    param([string]$Executable='scoop',[int]$TimeoutSeconds=30)
    $Executable = Resolve-WpaManagerExecutable -Manager scoop
    if(-not $Executable) { return [pscustomobject]@{manager='scoop';version=$null;status='failed';timedOut=$false;Packages=@();warning='scoop executable unavailable';Available=$false;Success=$false;Raw=$null} }
    $r=Invoke-WpaProcess -FilePath $Executable -Arguments @('export') -TimeoutSeconds $TimeoutSeconds -NoTruncateOutput
    $v=Invoke-WpaProcess -FilePath $Executable -Arguments @('--version') -TimeoutSeconds $TimeoutSeconds
    $u=Invoke-WpaProcess -FilePath $Executable -Arguments @('status','--local') -TimeoutSeconds $TimeoutSeconds -NoTruncateOutput
    $exportClean=(-not $r.TimedOut -and $r.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace([string]$r.StdErr))
    $versionClean=(-not $v.TimedOut -and $v.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace([string]$v.StdErr))
    $statusClean=(-not $u.TimedOut -and $u.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace([string]$u.StdErr))
    $packages=if($exportClean){ConvertFrom-WpaScoopExport $r.StdOut}else{$null}
    if($exportClean -and $null -eq $packages){$packages=ConvertFrom-WpaScoopFallback $r.StdOut}
    $managerVersion=if($versionClean){ConvertFrom-WpaScoopVersion $v.StdOut}else{$null}
    $updates=if($statusClean){ConvertFrom-WpaScoopStatus $u.StdOut}else{$null}
    if($packages -and $updates -and $updates.Valid){foreach($p in $packages){$m=$updates.Items|Where-Object Id -eq $p.Id|Select-Object -First 1;if($m){$p|Add-Member NoteProperty AvailableVersion $m.AvailableVersion -Force}}}
    $status=if($null -eq $packages){'failed'}elseif($null -eq $updates -or $null -eq $managerVersion){'partial'}else{'success'}
    $warnings=@()
    if($null -eq $packages){$warnings+='scoop export output unavailable or malformed'}
    if($null -eq $managerVersion){$warnings+='scoop version output unavailable or unrecognized'}
    if($null -eq $updates){$warnings+='scoop status output unavailable or unrecognized'}
    [pscustomobject]@{manager='scoop';version=$managerVersion;status=$status;timedOut=($r.TimedOut -or $u.TimedOut -or $v.TimedOut);Packages=@($packages | Where-Object {$null -ne $_} | ForEach-Object {[pscustomobject]@{manager='scoop';id=$_.Id;displayName=$_.Id;installedVersion=$_.Version;availableVersion=(Get-WpaPropertyValue $_ 'AvailableVersion');source=$_.Source;scope=$null;metadata=@{detectedBy='scoop-export'}}});warning=if($warnings.Count -gt 0){$warnings -join '; '}else{$null};Available=(Test-WpaScoopAvailable);Success=($null -ne $packages);Raw=$r}
}
function Install-WpaScoopPackage { [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30); if($Id -notmatch '^[A-Za-z0-9_.-]+$'){throw 'invalid id'}; $Executable=Resolve-WpaManagerExecutable -Manager scoop; if(-not $Executable){throw 'scoop executable unavailable'}; $spec=if($Source){"$Source/$Id"}else{$Id}; if($Version){$spec += "@$Version"};if($PSCmdlet.ShouldProcess("scoop/$Id",'install')){Invoke-WpaProcess -FilePath $Executable -Arguments @('install',$spec,'--no-update-scoop') -TimeoutSeconds $TimeoutSeconds} }
function Update-WpaScoopPackage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Version', Justification='The common manager upgrade adapter contract includes Version; Scoop update does not accept it.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Source', Justification='The common manager upgrade adapter contract includes Source; Scoop update uses the installed bucket.')]
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30)
    $Executable=Resolve-WpaManagerExecutable -Manager scoop
    if(-not $Executable){throw 'scoop executable unavailable'}
    if($PSCmdlet.ShouldProcess("scoop/$Id",'upgrade')){
        Invoke-WpaProcess -FilePath $Executable -Arguments @('update',$Id) -TimeoutSeconds $TimeoutSeconds
    }
}
