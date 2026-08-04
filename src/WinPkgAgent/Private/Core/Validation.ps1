function Assert-WpaPackageIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][ValidateSet('winget','scoop')][string]$Manager
    )
    if ($Value.Length -gt 200) { throw 'Package identifier exceeds 200 characters.' }
    $pattern = if ($Manager -eq 'winget') { '^[A-Za-z0-9][A-Za-z0-9._+-]{0,199}$' } else { '^[a-z0-9][a-z0-9._+-]{0,199}$' }
    if ($Value -cnotmatch $pattern) { throw "Invalid $Manager package identifier." }
    return $true
}

function Assert-WpaSourceName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Invalid package source name.' }
    return $true
}

function Assert-WpaVerification {
    [CmdletBinding()]
    param([AllowNull()][object]$Verification)
    if ($null -eq $Verification) { return $true }
    if ($Verification.command -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'Invalid verification command.' }
    $interpreter = [IO.Path]::GetFileNameWithoutExtension([string]$Verification.command).ToLowerInvariant()
    if ($interpreter -in @('pwsh','powershell','cmd','wscript','cscript','mshta','rundll32','regsvr32')) {
        throw 'Shells, script hosts, and system code loaders are not valid verification commands.'
    }
    $safeArguments = @('--version','-version','version','-v','-V','--help','-h','/?')
    foreach ($argument in @($Verification.arguments)) {
        if ($argument.Length -gt 200 -or $argument -match '[\r\n\0]' -or $argument -cnotin $safeArguments) {
            throw 'Verification arguments are limited to safe version or help switches.'
        }
    }
    return $true
}

function Test-WpaManifestObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Manifest)

    if ($Manifest.schemaVersion -ne 1) { throw 'Unsupported manifest schemaVersion.' }
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $owners = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($package in @($Manifest.packages)) {
        if ([string]::IsNullOrWhiteSpace($package.name) -or $package.name -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$') { throw 'Invalid logical package name.' }
        if (-not $names.Add([string]$package.name)) { throw "Duplicate logical package name: $($package.name)" }
        if ($package.manager -notin @('winget','scoop')) { throw "Unknown manager: $($package.manager)" }
        if ($package.state -ne 'present') { throw 'Only state present is supported in v0.1.' }
        Assert-WpaPackageIdentifier -Value $package.id -Manager $package.manager | Out-Null
        $source=Get-WpaPropertyValue $package 'source';if (-not $source) { throw 'Every package must declare an explicit source.' };Assert-WpaSourceName -Value $source | Out-Null
        $category=Get-WpaPropertyValue $package 'category';if (-not $category) { throw 'Every package must declare an explicit category.' }
        $version=Get-WpaPropertyValue $package 'version' 'latest';if ($version -and $version -ne 'latest' -and $version -notmatch '^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$') { throw 'Invalid package version.' }
        Assert-WpaVerification -Verification (Get-WpaPropertyValue $package 'verification') | Out-Null
        $ownerKey = "$($package.manager)`0$($package.id)"
        if (-not $owners.Add($ownerKey)) { throw "Duplicate manager package identifier: $($package.manager)/$($package.id)" }
    }
    return $true
}

function Assert-WpaPlanActionSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Actions)
    foreach($action in $Actions) {
        Assert-WpaPackageIdentifier -Value $action.id -Manager $action.manager | Out-Null
        $classification=[string]$action.classification
        $operation=Get-WpaPropertyValue $action 'operation'
        if($classification -in @('install','upgrade')) {
            if($operation -ne $classification) { throw 'Plan action classification and operation must match.' }
            if($action.manager -eq 'scoop' -and $classification -eq 'upgrade') { throw 'Scoop upgrades cannot enforce an exact approved target and are blocked in v0.1.' }
            $source=Get-WpaPropertyValue $action 'source'
            if(-not $source) { throw 'Mutating plan actions require an explicit source.' }
            Assert-WpaSourceName -Value $source | Out-Null
        } elseif($null -ne $operation) {
            throw 'Non-mutating plan classifications cannot contain an operation.'
        }
        $targetVersion=Get-WpaPropertyValue $action 'targetVersion'
        if($targetVersion -and $targetVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$') { throw 'Invalid plan target version.' }
        Assert-WpaVerification -Verification (Get-WpaPropertyValue $action 'verification') | Out-Null
    }
    return $true
}

function Test-WpaPolicyObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Policy)
    if ($Policy.schemaVersion -ne 1) { throw 'Unsupported policy schemaVersion.' }
    if ($Policy.allowUninstall -ne $false) { throw 'Uninstall must remain disabled in v0.1.' }
    if ($Policy.requireApproval -ne $true) { throw 'Approval must remain required in v0.1.' }
    if ($Policy.unknownVersionHandling -ne 'block') { throw 'Unknown versions must be blocked.' }
    if ('major' -in @($Policy.allowUpgrade)) { throw 'Major upgrades cannot be enabled in v0.1.' }
    foreach($requiredCategory in @('driver','bios','uefi','firmware')) {
        if($requiredCategory -notin @($Policy.dangerousCategories)) { throw "Dangerous category must remain blocked in v0.1: $requiredCategory" }
    }
    if ($Policy.rejectStateChanges -ne $true) { throw 'State-change rejection must remain enabled in v0.1.' }
    if ($Policy.rebootHandling -ne 'record-only') { throw 'Reboot handling must be record-only.' }
    if ($Policy.maxOperations -lt 1 -or $Policy.maxOperations -gt 100) { throw 'maxOperations must be between 1 and 100.' }
    if ($Policy.operationTimeoutSeconds -lt 30 -or $Policy.operationTimeoutSeconds -gt 7200) { throw 'operationTimeoutSeconds out of range.' }
    return $true
}
