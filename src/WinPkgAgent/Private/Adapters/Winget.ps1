function Test-WpaWingetAvailable { param([string]$Executable='winget'); $null -ne (Get-Command $Executable -ErrorAction SilentlyContinue) }
function ConvertFrom-WpaWingetExport {
    param([Parameter(Mandatory)][string]$Json)
    try { $data = $Json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $packages = @((Get-WpaPropertyValue $data 'Sources' @()) | ForEach-Object { Get-WpaPropertyValue $_ 'Packages' @() })
    if ($packages.Count -eq 0) { return $null }
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
    [pscustomobject]@{ manager='winget'; version=$managerVersion; status=$status; timedOut=($r.TimedOut -or $u.TimedOut -or $v.TimedOut); Packages=@($packages | Where-Object {$null -ne $_} | ForEach-Object {[pscustomobject]@{manager='winget';id=$_.Id;displayName=$_.Id;installedVersion=$_.Version;availableVersion=(Get-WpaPropertyValue $_ 'AvailableVersion');source=$_.Source;scope=$null;metadata=@{}}}); warning=if($null -eq $packages){'winget inventory unavailable or malformed'}elseif($null -eq $updates -or $null -eq $managerVersion){'winget version or update output unavailable or unrecognized'}else{$null}; Available=(Test-WpaWingetAvailable $Executable); Success=($null -ne $packages); Raw=$r }
}
function Install-WpaWingetPackage { [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30); if($Id -notmatch '^[A-Za-z0-9_.-]+$'){throw 'invalid id'}; $a=@('install','--id',$Id,'--exact','--disable-interactivity','--accept-source-agreements','--accept-package-agreements'); if($Version){$a+=@('--version',$Version)}; if($Source){$a+=@('--source',$Source)}; if($PSCmdlet.ShouldProcess("winget/$Id",'install')){Invoke-WpaProcess -FilePath 'winget' -Arguments $a -TimeoutSeconds $TimeoutSeconds} }
function Update-WpaWingetPackage { [CmdletBinding(SupportsShouldProcess)]param([string]$Id,[string]$Version,[string]$Source,[int]$TimeoutSeconds=30); $a=@('upgrade','--id',$Id,'--exact','--disable-interactivity','--accept-source-agreements','--accept-package-agreements'); if($Version){$a+=@('--version',$Version)}; if($Source){$a+=@('--source',$Source)}; if($PSCmdlet.ShouldProcess("winget/$Id",'upgrade')){Invoke-WpaProcess -FilePath 'winget' -Arguments $a -TimeoutSeconds $TimeoutSeconds} }
