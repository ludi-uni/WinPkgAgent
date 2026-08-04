function Resolve-WpaManagerExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('winget','scoop')][string]$Manager
    )

    $commandName = if($Manager -eq 'winget'){'winget'}else{'scoop'}
    foreach($command in @(Get-Command -Name $commandName -All -ErrorAction SilentlyContinue)) {
        $path = if($command.Path){[string]$command.Path}elseif($command.Source){[string]$command.Source}else{$null}
        if($path -and [System.IO.Path]::IsPathFullyQualified($path)){return $path}
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if($Manager -eq 'scoop' -and $env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd'))
    }
    if($Manager -eq 'winget') {
        if($env:LOCALAPPDATA) {$candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))}
    }
    foreach($candidate in $candidates | Select-Object -Unique) {
        if([System.IO.Path]::IsPathFullyQualified($candidate) -and (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue)) {return $candidate}
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
        $parent=Split-Path -LiteralPath $cursor.FullName -Parent
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
