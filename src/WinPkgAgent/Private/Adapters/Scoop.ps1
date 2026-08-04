function Test-WpaScoopAvailable { param([string]$Executable='scoop'); $null -ne (Get-Command $Executable -ErrorAction SilentlyContinue) }
function ConvertFrom-WpaScoopExport {
    param([Parameter(Mandatory)][string]$Json)
    try { $data = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $apps=Get-WpaPropertyValue $data 'apps';$items = if($data -is [System.Collections.IEnumerable] -and $data -isnot [string]){@($data)} elseif($apps){@($apps)} else {@($data)}
    $result = foreach($p in $items) {
        $id = Get-WpaPropertyValue $p 'name'; if([string]::IsNullOrWhiteSpace($id)){ $id=Get-WpaPropertyValue $p 'Name' }
        if([string]::IsNullOrWhiteSpace($id)){ return $null }
        $version=Get-WpaPropertyValue $p 'version';$bucket=Get-WpaPropertyValue $p 'bucket';[pscustomobject]@{Id=[string]$id;Version=if($version){[string]$version}else{$null};Manager='scoop';Source=if($bucket){[string]$bucket}else{$null}}
    }
    @($result)
}
function ConvertFrom-WpaScoopFallback {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text -notmatch '(?m)(Name\s+Version|\u540d\u524d\s+\u30d0\u30fc\u30b8\u30e7\u30f3)') { return $null }
    $rows=@(); foreach($line in ($Text -split "`r?`n")){ if($line -match '^(?<id>[A-Za-z0-9_.+-]+)\s+(?<version>\S+)$' -and $Matches.id -notmatch '^(?:Name|\u540d\u524d)$'){ $rows += [pscustomobject]@{Id=$Matches.id;Version=$Matches.version;Manager='scoop';Source=$null} } }
    if($rows.Count -eq 0){return $null};$rows
}
function ConvertFrom-WpaScoopStatus {
    param([string]$Text)
    if($Text -notmatch '(?mi)^\s*(Name\s{2,}Installed\s{2,}Latest|\u540d\u524d\s{2,}\u30a4\u30f3\u30b9\u30c8\u30fc\u30eb\u6e08\u307f\s{2,}\u6700\u65b0)'){return $null}
    $items=@()
    foreach($line in ($Text -split "`r?`n")){$columns=@($line.Trim() -split '\s{2,}');if($columns.Count -ge 3 -and $columns[0] -match '^[A-Za-z0-9][A-Za-z0-9._+-]{0,199}$' -and $columns[0] -ne 'Name'){$items+=[pscustomobject]@{Id=$columns[0];AvailableVersion=$columns[2]}}}
    [pscustomobject]@{Valid=$true;Items=@($items)}
}
function Get-WpaScoopInventory {
    param([string]$Executable='scoop',[int]$TimeoutSeconds=30)
    $r=Invoke-WpaProcess -FilePath $Executable -Arguments @('export') -TimeoutSeconds $TimeoutSeconds;$v=Invoke-WpaProcess -FilePath $Executable -Arguments @('--version') -TimeoutSeconds $TimeoutSeconds;$managerVersion=if($v.ExitCode -eq 0){$v.StdOut.Trim()}else{$null}
    $packages=if(-not $r.TimedOut -and $r.ExitCode -eq 0){ConvertFrom-WpaScoopExport $r.StdOut}else{$null}; if($null -eq $packages -and -not $r.TimedOut){$packages=ConvertFrom-WpaScoopFallback $r.StdOut}; $u=Invoke-WpaProcess -FilePath $Executable -Arguments @('status') -TimeoutSeconds $TimeoutSeconds; $updates=if($u.ExitCode -eq 0){ConvertFrom-WpaScoopStatus $u.StdOut}else{$null}; if($packages -and $null -ne $updates -and $updates.Valid){foreach($p in $packages){$m=$updates.Items|Where-Object Id -eq $p.Id|Select-Object -First 1;if($m){$p|Add-Member NoteProperty AvailableVersion $m.AvailableVersion -Force}}}
    $status=if($null -eq $packages){'failed'}elseif($null -eq $updates -or $null -eq $managerVersion){'partial'}else{'success'}
    [pscustomobject]@{manager='scoop';version=$managerVersion;status=$status;timedOut=($r.TimedOut -or $u.TimedOut -or $v.TimedOut);Packages=@($packages | Where-Object {$null -ne $_} | ForEach-Object {[pscustomobject]@{manager='scoop';id=$_.Id;displayName=$_.Id;installedVersion=$_.Version;availableVersion=(Get-WpaPropertyValue $_ 'AvailableVersion');source=$_.Source;scope=$null;metadata=@{}}});warning=if($null -eq $packages){'scoop inventory unavailable or malformed'}elseif($null -eq $updates -or $null -eq $managerVersion){'scoop version or status output unavailable or unrecognized'}else{$null};Available=(Test-WpaScoopAvailable $Executable);Success=($null -ne $packages);Raw=$r}
}
function Install-WpaScoopPackage { [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30); if($Id -notmatch '^[A-Za-z0-9_.-]+$'){throw 'invalid id'}; $spec=if($Source){"$Source/$Id"}else{$Id}; if($Version){$spec += "@$Version"};if($PSCmdlet.ShouldProcess("scoop/$Id",'install')){Invoke-WpaProcess -FilePath 'scoop' -Arguments @('install',$spec,'--no-update-scoop') -TimeoutSeconds $TimeoutSeconds} }
function Update-WpaScoopPackage { [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30); if($Id -notmatch '^[A-Za-z0-9_.-]+$'){throw 'invalid id'};$null=$Version;$null=$Source;if($PSCmdlet.ShouldProcess("scoop/$Id",'upgrade')){Invoke-WpaProcess -FilePath 'scoop' -Arguments @('update',$Id) -TimeoutSeconds $TimeoutSeconds} }
