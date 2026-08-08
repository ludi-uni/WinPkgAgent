function Test-WpaVerifiedExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if(-not [IO.Path]::IsPathFullyQualified($Path)){return $false}
    try {
        $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
        $cursor=$item
        while($null -ne $cursor){
            $parent=[IO.Path]::GetDirectoryName($cursor.FullName)
            if([string]::IsNullOrEmpty($parent) -or $parent -eq $cursor.FullName){break}
            $cursor=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
            if(($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
        }
        return $true
    } catch { return $false }
}

function Test-WpaWindowsAppsAlias {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)){return $false}
    try {
        $alias=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
        return [string]::Equals([IO.Path]::GetFullPath($Path),$alias,[StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Resolve-WpaManagerExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('winget','scoop')][string]$Manager
    )

    $commandName = if($Manager -eq 'winget'){'winget'}else{'scoop'}
    foreach($command in @(Get-Command -Name $commandName -All -ErrorAction SilentlyContinue)) {
        $path = Get-WpaPropertyValue $command 'Path'
        if([string]::IsNullOrWhiteSpace([string]$path)){$path = Get-WpaPropertyValue $command 'Source'}
        $path = if($null -ne $path){[string]$path}else{$null}
        if($Manager -eq 'scoop' -and $path -and [IO.Path]::GetExtension($path).ToLowerInvariant() -in @('.ps1','.psm1')){continue}
        if($path -and -not ($Manager -eq 'winget' -and (Test-WpaWindowsAppsAlias -Path $path)) -and (Test-WpaVerifiedExecutablePath -Path $path)){return [IO.Path]::GetFullPath($path)}
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if($Manager -eq 'scoop' -and $env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd'))
    }
    if($Manager -eq 'winget') {
        $packages=@(try { Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop } catch { @() })
        if($packages.Count -ne 1){return $null}
        $installLocation=[string](Get-WpaPropertyValue $packages[0] 'InstallLocation')
        if([string]::IsNullOrWhiteSpace($installLocation) -or -not [IO.Path]::IsPathFullyQualified($installLocation)){return $null}
        try {$candidates.Add((Join-Path $installLocation 'winget.exe'))} catch {return $null}
    }
    foreach($candidate in $candidates | Select-Object -Unique) {
        if((Test-WpaVerifiedExecutablePath -Path $candidate)) {return [IO.Path]::GetFullPath($candidate)}
    }
    return $null
}

function Get-WpaManagerFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('winget','scoop')][string]$Manager,[Parameter(Mandatory)][string]$Executable)
    if(-not [IO.Path]::IsPathFullyQualified($Executable)){throw 'Manager executable path must be absolute.'}
    $item=Get-Item -LiteralPath $Executable -Force -ErrorAction Stop
    if($item.PSIsContainer){throw 'Manager executable must be a file.'}
    $cursor=$item
    while($null -ne $cursor){
        if(($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Manager executable path contains a reparse point.'}
        $parent=[IO.Path]::GetDirectoryName($cursor.FullName)
        if([string]::IsNullOrEmpty($parent) -or $parent -eq $cursor.FullName){break}
        $cursor=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
    }
    $fullPath=[IO.Path]::GetFullPath($item.FullName);$bytes=[IO.File]::ReadAllBytes($fullPath)
    $fileHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    $version=try {[Diagnostics.FileVersionInfo]::GetVersionInfo($fullPath).FileVersion} catch {$null}
    $signatureStatus='not-applicable';$signerSubject=$null
    if($Manager -eq 'winget'){
        $signature=try {Get-AuthenticodeSignature -LiteralPath $fullPath -ErrorAction Stop} catch {$null}
        if($null -eq $signature){$signatureStatus='unavailable'}else{$signatureStatus=[string]$signature.Status;$signerSubject=if($signature.SignerCertificate){[string]$signature.SignerCertificate.Subject}else{$null}}
    }
    $aclAssessment='unknown'
    try {
        $acl = Get-Acl -LiteralPath $fullPath -ErrorAction Stop
        $owner=[string]$acl.Owner
        $protectedOwner=$owner -match '^(NT SERVICE\\TrustedInstaller|NT AUTHORITY\\SYSTEM|BUILTIN\\Administrators)$'
        $broadWrite=$false
        foreach($rule in @($acl.Access)){
            $identity=[string]$rule.IdentityReference
            $rights=[string]$rule.FileSystemRights
            if($rule.AccessControlType -eq 'Allow' -and $identity -match '(?i)(^|\\)(Everyone|Users|Authenticated Users)$' -and $rights -match '(?i)(Write|Modify|FullControl|Delete)'){$broadWrite=$true;break}
        }
        if($protectedOwner -and -not $broadWrite){$aclAssessment='trusted;acl-checked'}
    } catch {
        $aclAssessment='unknown'
    }
    if($Manager -eq 'scoop' -and $fullPath -match '\.(?:cmd|bat)$'){
        $text=[Text.Encoding]::ASCII.GetString($bytes)
        $match=[regex]::Match($text,'(?im)^\s*(?:call\s+)?(?<quote>["''])(?<target>(?:(?!\k<quote>).)+)\k<quote>\s+%\*\s*$')
        if(-not $match.Success){
            $signatureStatus='MANAGER_FINGERPRINT_UNAVAILABLE'
        }else{
            $target=$match.Groups['target'].Value
            if($target -match '[;&|<>`]' -or -not [IO.Path]::IsPathFullyQualified($target) -or -not (Test-Path -LiteralPath $target -PathType Leaf)){throw 'Scoop forwarding target is unavailable.'}
            $targetItem=Get-Item -LiteralPath $target -Force
            if(($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Scoop forwarding target is a reparse point.'}
            $targetHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($targetItem.FullName))).ToLowerInvariant()
            $aclAssessment="trusted;forwardingTargetSha256=$targetHash"
        }
    }
    [pscustomobject][ordered]@{manager=$Manager;pathHash=(Get-WpaSha256 -Text $fullPath.ToLowerInvariant());fileSha256=$fileHash;fileVersion=$version;lastWriteTimeUtc=$item.LastWriteTimeUtc.ToString('o');fileLength=[int64]$item.Length;isReparsePoint=$false;signatureStatus=$signatureStatus;signerSubject=$signerSubject;aclAssessment=$aclAssessment}
}
