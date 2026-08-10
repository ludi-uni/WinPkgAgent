function ConvertTo-WpaAction {
    param([object]$Package,[string]$Classification,[AllowNull()][object]$Operation,[string]$ReasonCode,[string]$Reason,[string]$Risk='low',[AllowNull()][object]$TargetVersion=$null)
    [pscustomobject][ordered]@{
        name = $Package.name; manager = $Package.manager; id = $Package.id; source = (Get-WpaPropertyValue $Package 'source')
        classification = $Classification; operation = $Operation; reasonCode = $ReasonCode
        reason = $Reason; risk = $Risk; targetVersion = $TargetVersion
        verification = (Get-WpaPropertyValue $Package 'verification')
    }
}

function Get-WpaPlanEvaluation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Manifest,[Parameter(Mandatory)][object]$Policy,[Parameter(Mandatory)][object]$Inventory)
    $actions = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $declared = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $protected = @($Policy.protectedPackages)
    $dangerous = @(@($Policy.dangerousCategories) + @('driver','bios','uefi','firmware') | Select-Object -Unique)

    $productKeys=@{}
    foreach($candidate in @($Manifest.packages)){
        $lastId=([string]$candidate.id -split '[./]')[-1]
        $productKey=(([string]$candidate.name+$lastId).ToLowerInvariant() -replace '[^a-z0-9]','')
        if($productKeys.ContainsKey($productKey) -and $productKeys[$productKey] -ne $candidate.manager){$warnings.Add("Possible cross-manager duplicate product: $($candidate.name) ($($productKeys[$productKey]) and $($candidate.manager)).")}
        else{$productKeys[$productKey]=$candidate.manager}
    }

    foreach ($package in @($Manifest.packages)) {
        $key = "$($package.manager)`0$($package.id)"; $null = $declared.Add($key)
        if ($package.manager -notin @($Policy.allowedManagers)) {
            $actions.Add((ConvertTo-WpaAction $package blocked $null MANAGER_NOT_ALLOWED 'The package manager is not allowed by policy.' high)); continue
        }
        $managerScope = @(Get-WpaPropertyValue $Inventory 'managerScope' @())
        if ($managerScope.Count -gt 0 -and $package.manager -notin $managerScope) {
            $actions.Add((ConvertTo-WpaAction $package blocked $null MANAGER_UNAVAILABLE 'The declared package manager is outside the inventory scope.' high)); continue
        }
        $managerState = @($Inventory.managers | Where-Object { (Get-WpaPropertyValue $_ 'manager' (Get-WpaPropertyValue $_ 'Name')) -eq $package.manager }) | Select-Object -First 1
        $managerStatus = Get-WpaPropertyValue $managerState 'status' $(if (Get-WpaPropertyValue $managerState 'Success' $false) { 'success' } else { 'failed' })
        if ($null -eq $managerState -or $managerStatus -ne 'success') {
            $actions.Add((ConvertTo-WpaAction $package blocked $null MANAGER_UNAVAILABLE 'The declared package manager inventory is unavailable.' high)); continue
        }
        $packageSource=Get-WpaPropertyValue $package 'source'
        if ($packageSource -and $packageSource -notin @($Policy.allowedSources)) {
            $actions.Add((ConvertTo-WpaAction $package blocked $null SOURCE_NOT_ALLOWED 'The package source is not allowed by policy.' high)); continue
        }
        $category = Get-WpaPropertyValue $package 'category'
        if ($category -and $category -in $dangerous) {
            $actions.Add((ConvertTo-WpaAction $package blocked $null DANGEROUS_CATEGORY_BLOCKED 'The package category is denied by policy.' critical)); continue
        }
        $isProtected = ($package.name -in $protected) -or ($package.id -in $protected) -or [bool](Get-WpaPropertyValue $package 'protected' $false)
        $installed = @($Inventory.packages | Where-Object { $_.manager -eq $package.manager -and $_.id -eq $package.id }) | Select-Object -First 1
        if ($null -eq $installed) {
            if (-not $Policy.allowInstall) { $actions.Add((ConvertTo-WpaAction $package blocked $null INSTALL_NOT_ALLOWED 'Package installation is disabled by policy.' high)); continue }
            if ($isProtected) { $actions.Add((ConvertTo-WpaAction $package blocked $null PROTECTED_PACKAGE 'The package is protected by policy.' high)); continue }
            $declaredVersion=Get-WpaPropertyValue $package 'version' 'latest';$target = if ($declaredVersion -eq 'latest') { $null } else { $declaredVersion }
            $actions.Add((ConvertTo-WpaAction $package install install PACKAGE_NOT_INSTALLED 'The declared package is not installed.' low $target)); continue
        }
        $installedVersion = Get-WpaPropertyValue $installed 'installedVersion' (Get-WpaPropertyValue $installed 'Version')
        $availableVersion = Get-WpaPropertyValue $installed 'availableVersion'
        $declaredVersion=Get-WpaPropertyValue $package 'version' 'latest';if ($declaredVersion -ne 'latest') { $availableVersion = $declaredVersion }
        if ([string]::IsNullOrWhiteSpace($availableVersion) -or $availableVersion -eq $installedVersion) {
            $actions.Add((ConvertTo-WpaAction $package 'no-op' $null VERSION_ALREADY_SATISFIED 'The installed version already satisfies the declaration.' none $installedVersion)); continue
        }
        if ($isProtected) { $actions.Add((ConvertTo-WpaAction $package blocked $null PROTECTED_PACKAGE 'The package is protected by policy.' high $availableVersion)); continue }
        $change = Compare-WpaVersionChange -InstalledVersion $installedVersion -AvailableVersion $availableVersion
        if ($change -eq 'unknown') { $actions.Add((ConvertTo-WpaAction $package blocked $null UNPARSEABLE_VERSION_BLOCKED 'The version change cannot be classified safely.' high $availableVersion)); continue }
        if ($change -eq 'major') { $actions.Add((ConvertTo-WpaAction $package blocked $null MAJOR_UPGRADE_BLOCKED 'Major upgrades are denied by policy.' high $availableVersion)); continue }
        if ($package.manager -eq 'scoop') { $actions.Add((ConvertTo-WpaAction $package blocked $null SCOOP_TARGET_VERSION_UNENFORCEABLE 'Scoop update cannot pin the exact approved target version; the upgrade is blocked in v0.1.' high $availableVersion)); continue }
        if ($change -notin @($Policy.allowUpgrade)) { $actions.Add((ConvertTo-WpaAction $package blocked $null UPGRADE_CLASS_NOT_ALLOWED "The $change upgrade is not allowed by policy." high $availableVersion)); continue }
        $reasonCode = if ($change -eq 'minor') { 'MINOR_UPGRADE_AVAILABLE' } else { 'PATCH_UPGRADE_AVAILABLE' }
        $actions.Add((ConvertTo-WpaAction $package upgrade upgrade $reasonCode "A policy-allowed $change upgrade is available." medium $availableVersion))
    }

    foreach ($installed in @($Inventory.packages)) {
        $key = "$($installed.manager)`0$($installed.id)"
        if (-not $declared.Contains($key)) {
            $placeholder = [pscustomobject]@{ name=$installed.displayName;manager=$installed.manager;id=$installed.id;source=$installed.source;verification=$null }
            $actions.Add((ConvertTo-WpaAction $placeholder unmanaged $null UNMANAGED_PACKAGE_REPORTED 'The installed package is outside the declaration and will not be removed.' none))
        }
    }

    $actionable = @($actions | Where-Object classification -in @('install','upgrade'))
    if ($actionable.Count -gt $Policy.maxOperations) {
        foreach ($action in $actionable) {
            $action.classification='blocked'; $action.operation=$null; $action.reasonCode='MAX_OPERATIONS_EXCEEDED'; $action.reason='The plan exceeds the policy maximum operation count.'; $action.risk='high'
        }
        $warnings.Add('The maximum operation count was exceeded; all mutating candidates were blocked.')
    }
    [pscustomobject]@{ actions=@($actions); blockedOperations=@($actions | Where-Object classification -eq blocked); warnings=@($warnings) }
}

function Get-WpaPlanContent {
    param([Parameter(Mandatory)][object]$Plan)
    [ordered]@{
        schemaVersion=$Plan.schemaVersion; toolVersion=$Plan.toolVersion; environmentId=$Plan.environmentId
        manifestHash=$Plan.manifestHash; policyHash=$Plan.policyHash; inventoryHash=$Plan.inventoryHash
        actions=@($Plan.actions); blockedOperations=@($Plan.blockedOperations); warnings=@($Plan.warnings)
    }
}

function Get-WpaPlanHashInput {
    param([Parameter(Mandatory)][object]$Plan)
    $ordered=[ordered]@{}
    foreach($property in $Plan.PSObject.Properties | Where-Object Name -ne 'planHash' | Sort-Object Name -CaseSensitive){$ordered[$property.Name]=$property.Value}
    $ordered
}

function Assert-WpaPlanIntegrity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Plan)
    $contentHash=Get-WpaObjectHash (Get-WpaPlanContent $Plan)
    if($contentHash -ne $Plan.contentHash){throw 'Plan content hash mismatch.'}
    $planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $Plan)
    if($planHash -ne $Plan.planHash){throw 'Plan hash mismatch.'}
    return $true
}
