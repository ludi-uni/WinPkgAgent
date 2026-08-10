function Get-WpaPowerShellCandidateLabel {
    @('current-process','configured','path','program-files','preview','windows-app-alias','dotnet-tool')
}

function Get-WpaPowerShellFileFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if(-not [IO.Path]::IsPathFullyQualified($Path)){throw 'PowerShell executable path must be absolute.'}
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer){throw 'PowerShell executable must be a file.'}
    $cursor=$item
    while($null -ne $cursor){
        if(($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'PowerShell executable path contains a reparse point.'}
        $parent=[IO.Path]::GetDirectoryName($cursor.FullName)
        if([string]::IsNullOrEmpty($parent) -or $parent -eq $cursor.FullName){break}
        $cursor=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
    }
    $fullPath=[IO.Path]::GetFullPath($item.FullName);$bytes=[IO.File]::ReadAllBytes($fullPath)
    $signatureStatus='unavailable';$signerSubject=$null
    try{$signature=Get-AuthenticodeSignature -LiteralPath $fullPath -ErrorAction Stop;if($null -ne $signature){$signatureStatus=[string]$signature.Status;$signerSubject=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{$null}}}catch{Write-Verbose 'Authenticode metadata was unavailable; the fingerprint retains unavailable signature evidence.'}
    [pscustomobject][ordered]@{resolvedPath=$fullPath;pathHash=(Get-WpaSha256 -Text $fullPath.ToLowerInvariant());fileSha256=([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant();fileLength=[int64]$item.Length;lastWriteTimeUtc=$item.LastWriteTimeUtc.ToString('o');signatureStatus=$signatureStatus;signerSubject=$signerSubject;isReparsePoint=$false}
}

function Test-WpaPowerShellExecutable {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Path,
        [Parameter(Mandatory)][ValidateSet('current-process','configured','path','program-files','preview','windows-app-alias','dotnet-tool')][string]$Source,
        [AllowNull()][string]$ProbeJson
    )
    $base=[ordered]@{available=$false;compatible=$false;resolvedPath=$Path;version=$null;edition=$null;source=$Source;pathHash=$null;fileSha256=$null;fileLength=$null;lastWriteTimeUtc=$null;signatureStatus=$null;signerSubject=$null;isReparsePoint=$null;reasonCode=$null;reason=$null;checkedCandidates=@()}
    if($Path){
        if(-not [IO.Path]::IsPathFullyQualified($Path)){$base.reasonCode='CONFIGURED_POWERSHELL_PATH_NOT_ABSOLUTE';$base.reason='PowerShell path must be absolute.';return [pscustomobject]$base}
        if($Source -ne 'current-process' -and [IO.Path]::GetFileName($Path) -cne 'pwsh.exe'){$base.reasonCode='CONFIGURED_POWERSHELL_INVALID';$base.reason='The configured executable must be named pwsh.exe.';return [pscustomobject]$base}
        if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){$base.reasonCode=if($Source -eq 'configured'){'CONFIGURED_POWERSHELL_NOT_FOUND'}else{'POWERSHELL_7_NOT_FOUND'};$base.reason='PowerShell executable was not found.';return [pscustomobject]$base}
        try{$fingerprint=Get-WpaPowerShellFileFingerprint -Path $Path}catch{$base.reasonCode=if($Source -eq 'configured' -and $_.Exception.Message -like '*reparse*'){'CONFIGURED_POWERSHELL_IS_REPARSE_POINT'}elseif($Source -eq 'configured'){'CONFIGURED_POWERSHELL_INVALID'}else{'POWERSHELL_7_NOT_FOUND'};$base.reason=$_.Exception.Message;return [pscustomobject]$base}
        foreach($property in @('pathHash','fileSha256','fileLength','lastWriteTimeUtc','signatureStatus','signerSubject','isReparsePoint')){$base[$property]=$fingerprint.$property}
    }
    if($Source -eq 'current-process' -and -not $ProbeJson){$payload=[pscustomobject]@{PSEdition=$PSVersionTable.PSEdition;PSVersion=$PSVersionTable.PSVersion.ToString()}}
    else{
        if(-not $ProbeJson){$process=Invoke-WpaProcess -FilePath $Path -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command','$PSVersionTable | ConvertTo-Json -Compress') -TimeoutSeconds 15;if($process.TimedOut){$base.reasonCode='POWERSHELL_PROBE_TIMEOUT';$base.reason='PowerShell runtime probe timed out.';return [pscustomobject]$base};if($process.ExitCode -ne 0){$base.reasonCode='POWERSHELL_PROBE_FAILED';$base.reason='PowerShell runtime probe failed.';return [pscustomobject]$base};$ProbeJson=$process.StdOut}
        try{$payload=$ProbeJson|ConvertFrom-Json -ErrorAction Stop}catch{$base.reasonCode='POWERSHELL_PROBE_INVALID_JSON';$base.reason='PowerShell runtime probe returned invalid JSON.';return [pscustomobject]$base}
    }
    try {
        $versionValue=Get-WpaPropertyValue $payload 'PSVersion' $null
        if($versionValue -is [string]){$version=[version]$versionValue}
        elseif($null -ne $versionValue -and $null -ne (Get-WpaPropertyValue $versionValue 'Major' $null)) {
            $version=[version]::new([int](Get-WpaPropertyValue $versionValue 'Major' 0),[int](Get-WpaPropertyValue $versionValue 'Minor' 0),[int](Get-WpaPropertyValue $versionValue 'Patch' 0))
        } else { throw 'PowerShell runtime version was missing.' }
    } catch {$base.reasonCode=if($Source -eq 'configured'){'CONFIGURED_POWERSHELL_INVALID_VERSION'}else{'POWERSHELL_VERSION_TOO_OLD'};$base.reason='PowerShell runtime version was invalid.';return [pscustomobject]$base}
    $base.version=$version.ToString();$base.edition=[string](Get-WpaPropertyValue $payload 'PSEdition' '')
    if($base.edition -ne 'Core'){$base.reasonCode=if($Source -eq 'configured'){'CONFIGURED_POWERSHELL_INVALID_VERSION'}else{'POWERSHELL_EDITION_UNSUPPORTED'};$base.reason='Windows PowerShell Desktop is not supported; pwsh.exe with Core is required.';return [pscustomobject]$base}
    if($version -lt [version]'7.4.0'){$base.reasonCode=if($Source -eq 'configured'){'CONFIGURED_POWERSHELL_INVALID_VERSION'}else{'POWERSHELL_VERSION_TOO_OLD'};$base.reason='PowerShell 7.4 or newer is required.';return [pscustomobject]$base}
    $base.available=$true;$base.compatible=$true;return [pscustomobject]$base
}

function Resolve-WpaPowerShellExecutable {
    [CmdletBinding()]
    param([AllowNull()][string]$PowerShellPath)
    $labels=Get-WpaPowerShellCandidateLabel
    if($PowerShellPath){$configured=Test-WpaPowerShellExecutable -Path $PowerShellPath -Source configured;if(-not $configured.compatible){throw "$($configured.reasonCode): $($configured.reason)"};return $configured}
    if($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion -ge [version]'7.4.0'){
        $currentPath=[Environment]::ProcessPath;$current=Test-WpaPowerShellExecutable -Path $currentPath -Source current-process;if($current.compatible){return $current}
    }
    $candidates=[System.Collections.Generic.List[object]]::new()
    foreach($command in @(Get-Command -Name 'pwsh.exe' -CommandType Application -All -ErrorAction SilentlyContinue)){$path=if($command.Path){[string]$command.Path}elseif($command.Source){[string]$command.Source}else{$null};if($path){$candidates.Add([pscustomobject]@{Path=$path;Source='path'})}}
    $programFiles=@($env:ProgramFiles,$env:ProgramW6432)|Where-Object {$_}|Select-Object -Unique
    foreach($root in $programFiles){$candidates.Add([pscustomobject]@{Path=(Join-Path $root 'PowerShell\7\pwsh.exe');Source='program-files'});$candidates.Add([pscustomobject]@{Path=(Join-Path $root 'PowerShell\7-preview\pwsh.exe');Source='preview'})}
    if($env:LOCALAPPDATA){$candidates.Add([pscustomobject]@{Path=(Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe');Source='windows-app-alias'})}
    if($env:USERPROFILE){$candidates.Add([pscustomobject]@{Path=(Join-Path $env:USERPROFILE '.dotnet\tools\pwsh.exe');Source='dotnet-tool'})}
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($candidate in $candidates){if($seen.Add($candidate.Path)){$result=Test-WpaPowerShellExecutable -Path $candidate.Path -Source $candidate.Source;if($result.compatible){return $result}}}
    $windowsPowerShell=Get-Command -Name 'powershell.exe' -CommandType Application -ErrorAction SilentlyContinue
    $reasonCode=if($windowsPowerShell){'WINDOWS_POWERSHELL_NOT_SUPPORTED'}else{'POWERSHELL_7_NOT_FOUND'}
    $reason=if($windowsPowerShell){'Windows PowerShell 5.1 was found, but WinPkgAgent requires PowerShell 7.4 or newer. The required executable is pwsh.exe, not powershell.exe.'}{'PowerShell 7.4 or newer was not found.'}
    throw "$reasonCode`: $reason Checked: $($labels -join ', '). WinPkgAgent did not modify PATH. Configure runtime.powershellPath with an absolute pwsh.exe path or restart the host after installing PowerShell 7.4+."
}

function Get-WpaPowerShellRuntimeInfo {
    [CmdletBinding()]
    param([AllowNull()][string]$PowerShellPath)
    try{return Resolve-WpaPowerShellExecutable -PowerShellPath $PowerShellPath}catch{$message=$_.Exception.Message;$code=if($message -match '^([A-Z0-9_]+):'){$Matches[1]}else{'POWERSHELL_7_NOT_FOUND'};return [pscustomobject][ordered]@{available=$false;compatible=$false;version=$null;edition=$null;source=$null;pathHash=$null;fileSha256=$null;fileLength=$null;lastWriteTimeUtc=$null;signatureStatus=$null;signerSubject=$null;isReparsePoint=$null;reasonCode=$code;reason=$message;checkedCandidates=Get-WpaPowerShellCandidateLabel}}
}

function ConvertTo-WpaPowerShellRuntimeArtifact {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Runtime)
    [pscustomobject][ordered]@{available=[bool]$Runtime.available;compatible=[bool]$Runtime.compatible;version=$Runtime.version;edition=$Runtime.edition;source=$Runtime.source;pathHash=$Runtime.pathHash;fileSha256=$Runtime.fileSha256;fileLength=$Runtime.fileLength;lastWriteTimeUtc=$Runtime.lastWriteTimeUtc;signatureStatus=$Runtime.signatureStatus;signerSubject=$Runtime.signerSubject;isReparsePoint=$Runtime.isReparsePoint;reasonCode=$Runtime.reasonCode;reason=$Runtime.reason;checkedCandidates=@(Get-WpaPropertyValue $Runtime 'checkedCandidates' @())}
}
