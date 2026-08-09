function New-WpaPlanObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][object]$Policy,
        [Parameter(Mandatory)][object]$Inventory,
        [datetimeoffset]$Now=[datetimeoffset]::UtcNow
    )
    $policyHash=Get-WpaObjectHash $Policy
    $inventoryPolicyHash=[string](Get-WpaPropertyValue $Inventory 'policyHash')
    $managerScope=@(Get-WpaPropertyValue $Inventory 'managerScope' @() | ForEach-Object {[string]$_})
    $allowedDeclaredManagers=@($Manifest.packages | ForEach-Object { [string](Get-WpaPropertyValue $_ 'manager') } | Where-Object { $_ -in @($Policy.allowedManagers) } | Sort-Object -Unique)
    if($inventoryPolicyHash -ne $policyHash -or @($allowedDeclaredManagers | Where-Object { $_ -notin $managerScope }).Count -gt 0){throw 'INVENTORY_SCOPE_MISMATCH'}
    foreach($manager in $allowedDeclaredManagers){
        $inventoryManager=@($Inventory.managers | Where-Object { (Get-WpaPropertyValue $_ 'manager') -eq $manager } | Select-Object -First 1)
        if($inventoryManager.Count -eq 0){throw "MANAGER_FINGERPRINT_UNAVAILABLE: $manager"}
        Assert-WpaManagerFingerprintEvidence -Manager $manager -Fingerprint (Get-WpaPropertyValue $inventoryManager[0] 'fingerprint') | Out-Null
    }
    $evaluation=Get-WpaPlanEvaluation -Manifest $Manifest -Policy $Policy -Inventory $Inventory
    $expires=$Now.AddMinutes([int]$Policy.approvalValidityMinutes)
    $plan=[pscustomobject][ordered]@{
        schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt=$Now.ToUniversalTime().ToString('o');expiresAt=$expires.ToUniversalTime().ToString('o')
        environmentId=$Inventory.environment.id;manifestHash=(Get-WpaObjectHash $Manifest);policyHash=$policyHash;inventoryHash=(Get-WpaInventoryStateHash $Inventory);managerFingerprints=@($Inventory.managers | ForEach-Object {[pscustomobject]@{manager=$_.manager;fingerprint=(Get-WpaPropertyValue $_ 'fingerprint')}})
        actions=@($evaluation.actions);blockedOperations=@($evaluation.blockedOperations);warnings=@($evaluation.warnings);contentHash=$null;planHash=$null
    }
    $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan)
    $plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
    Assert-WpaPlanActionSet -Actions @($plan.actions) | Out-Null
    Test-WpaDataSchema $plan plan | Out-Null
    return $plan
}
