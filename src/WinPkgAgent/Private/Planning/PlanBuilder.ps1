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
    $rawManagerScope=@(Get-WpaPropertyValue $Inventory 'managerScope' @() | ForEach-Object {([string]$_).ToLowerInvariant()})
    $managerScope=@($rawManagerScope | Sort-Object -Unique)
    $selectedManagers=@($Policy.allowedManagers | ForEach-Object {([string]$_).ToLowerInvariant()} | Sort-Object -Unique)
    $inventoryStatus=[string](Get-WpaPropertyValue $Inventory 'status' '')
    if($inventoryPolicyHash -ne $policyHash -or $inventoryStatus -cne 'success' -or $rawManagerScope.Count -ne $managerScope.Count -or $managerScope.Count -ne $selectedManagers.Count){throw 'INVENTORY_SCOPE_MISMATCH'}
    for($index=0;$index -lt $selectedManagers.Count;$index++){
        if(-not [string]::Equals($managerScope[$index],$selectedManagers[$index],[StringComparison]::Ordinal)){throw 'INVENTORY_SCOPE_MISMATCH'}
    }
    $inventoryManagers=@(Get-WpaPropertyValue $Inventory 'managers' @())
    foreach($manager in $selectedManagers){
        $inventoryManager=@($inventoryManagers | Where-Object {[string]::Equals([string](Get-WpaPropertyValue $_ 'manager'),$manager,[StringComparison]::Ordinal)})
        if($inventoryManager.Count -ne 1 -or [string](Get-WpaPropertyValue $inventoryManager[0] 'status' '') -cne 'success'){throw "MANAGER_FINGERPRINT_UNAVAILABLE: $manager"}
        $fingerprint=Get-WpaPropertyValue $inventoryManager[0] 'fingerprint'
        $fingerprintManager=[string](Get-WpaPropertyValue $fingerprint 'manager' '')
        if(-not [string]::Equals($fingerprintManager,$manager,[StringComparison]::Ordinal)){throw "MANAGER_FINGERPRINT_UNAVAILABLE: $manager"}
        Assert-WpaManagerFingerprintEvidence -Manager $manager -Fingerprint $fingerprint | Out-Null
    }
    if($inventoryManagers.Count -ne $selectedManagers.Count){throw 'INVENTORY_SCOPE_MISMATCH'}
    $evaluation=Get-WpaPlanEvaluation -Manifest $Manifest -Policy $Policy -Inventory $Inventory
    $expires=$Now.AddMinutes([int]$Policy.approvalValidityMinutes)
    $plan=[pscustomobject][ordered]@{
        schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt=$Now.ToUniversalTime().ToString('o');expiresAt=$expires.ToUniversalTime().ToString('o')
        environmentId=$Inventory.environment.id;manifestHash=(Get-WpaObjectHash $Manifest);policyHash=$policyHash;inventoryHash=(Get-WpaInventoryStateHash $Inventory);managerFingerprints=@($inventoryManagers | ForEach-Object {[pscustomobject]@{manager=$_.manager;fingerprint=(Get-WpaPropertyValue $_ 'fingerprint')}})
        actions=@($evaluation.actions);blockedOperations=@($evaluation.blockedOperations);warnings=@($evaluation.warnings);contentHash=$null;planHash=$null
    }
    $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan)
    $plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
    Assert-WpaPlanActionSet -Actions @($plan.actions) | Out-Null
    Test-WpaDataSchema $plan plan | Out-Null
    return $plan
}
