function New-WpaPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$PolicyPath,
        [Parameter(Mandatory)][string]$InventoryPath,[Parameter(Mandatory)][string]$OutputPath,
        [string]$MarkdownPath,[datetimeoffset]$Now=[datetimeoffset]::UtcNow
    )
    $manifest=Read-WpaManifestResolved $ManifestPath; Test-WpaManifestObject $manifest | Out-Null; Test-WpaDataSchema $manifest manifest | Out-Null
    if(-not $MarkdownPath){$MarkdownPath=[IO.Path]::ChangeExtension($OutputPath,'.md')}
    $policy=Read-WpaPolicyFile $PolicyPath; Test-WpaDataSchema $policy policy | Out-Null
    $inventory=ConvertTo-WpaInventoryBoundary (Read-WpaJsonFile $InventoryPath); Test-WpaDataSchema $inventory inventory | Out-Null
    $policyHash=Get-WpaObjectHash $policy
    $inventoryPolicyHash=[string](Get-WpaPropertyValue $inventory 'policyHash')
    $managerScope=@(Get-WpaPropertyValue $inventory 'managerScope' @() | ForEach-Object {[string]$_})
    $allowedDeclaredManagers=@($manifest.packages | ForEach-Object { [string](Get-WpaPropertyValue $_ 'manager') } | Where-Object { $_ -in @($policy.allowedManagers) } | Sort-Object -Unique)
    if($inventoryPolicyHash -ne $policyHash -or @($allowedDeclaredManagers | Where-Object { $_ -notin $managerScope }).Count -gt 0){throw 'INVENTORY_SCOPE_MISMATCH'}
    foreach($manager in $allowedDeclaredManagers){
        $inventoryManager=@($inventory.managers | Where-Object { (Get-WpaPropertyValue $_ 'manager') -eq $manager } | Select-Object -First 1)
        if($inventoryManager.Count -eq 0){throw "MANAGER_FINGERPRINT_UNAVAILABLE: $manager"}
        Assert-WpaManagerFingerprintEvidence -Manager $manager -Fingerprint (Get-WpaPropertyValue $inventoryManager[0] 'fingerprint') | Out-Null
    }
    $evaluation=Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
    $expires=$Now.AddMinutes([int]$policy.approvalValidityMinutes)
    $plan=[pscustomobject][ordered]@{
        schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt=$Now.ToUniversalTime().ToString('o');expiresAt=$expires.ToUniversalTime().ToString('o')
        environmentId=$inventory.environment.id;manifestHash=(Get-WpaObjectHash $manifest);policyHash=(Get-WpaObjectHash $policy);inventoryHash=(Get-WpaInventoryStateHash $inventory);managerFingerprints=@($inventory.managers | ForEach-Object {[pscustomobject]@{manager=$_.manager;fingerprint=(Get-WpaPropertyValue $_ 'fingerprint')}})
        actions=@($evaluation.actions);blockedOperations=@($evaluation.blockedOperations);warnings=@($evaluation.warnings);contentHash=$null;planHash=$null
    }
    $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan)
    $plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
    Assert-WpaPlanActionSet -Actions @($plan.actions) | Out-Null
    Test-WpaDataSchema $plan plan | Out-Null
    if($PSCmdlet.ShouldProcess($OutputPath,'Write immutable plan artifact')){Write-WpaAtomicJson $OutputPath $plan}
    if($MarkdownPath -and $PSCmdlet.ShouldProcess($MarkdownPath,'Write human-readable plan')){Write-WpaAtomicText $MarkdownPath (ConvertTo-WpaPlanMarkdown $plan)}
    return $plan
}

function ConvertTo-WpaPlanMarkdown {
    param([Parameter(Mandatory)][object]$Plan)
    $actions=@(Get-WpaPropertyValue $Plan 'actions' @());$blocked=@(Get-WpaPropertyValue $Plan 'blockedOperations' @());$warnings=@(Get-WpaPropertyValue $Plan 'warnings' @());$unknown=@($actions|Where-Object {(Get-WpaPropertyValue $_ 'classification') -eq 'unknown' -or (Get-WpaPropertyValue $_ 'reasonCode' '') -match 'UNKNOWN'});$high=@($actions|Where-Object {(Get-WpaPropertyValue $_ 'risk') -eq 'high'});$reboot=@($actions|Where-Object {[bool](Get-WpaPropertyValue $_ 'rebootRequired' $false) -or (Get-WpaPropertyValue $_ 'reasonCode' '') -match 'REBOOT'})
    $lines=@('# winpkg-agent plan','',"Plan ID: $($Plan.planId)","Expires: $($Plan.expiresAt)","Changes: $($actions.Count)","Blocked: $($blocked.Count)","Unknown: $($unknown.Count)","High risk: $($high.Count)","Reboot possible: $(if($reboot.Count -gt 0){'yes'}else{'no'})",'','## Actions','','| Package | Manager ID | Source | Classification / operation | Target | Verification | Risk | Reason |','|---|---|---|---|---|---|---|---|')
    $order=@{'blockedOperations'=0;'unknown'=1;'high'=2;'upgrade'=3;'install'=4;'unmanaged'=5;'no-op'=6}
    $ordered=@($blocked|ForEach-Object {[pscustomobject]@{name=(Get-WpaPropertyValue $_ 'name' '-');manager=(Get-WpaPropertyValue $_ 'manager' '-');id=(Get-WpaPropertyValue $_ 'id' '-');source=(Get-WpaPropertyValue $_ 'source' '-');classification='blocked';operation=(Get-WpaPropertyValue $_ 'operation');targetVersion=(Get-WpaPropertyValue $_ 'targetVersion');verification=(Get-WpaPropertyValue $_ 'verification');risk=(Get-WpaPropertyValue $_ 'risk' '-');reasonCode=(Get-WpaPropertyValue $_ 'reasonCode' '');reason=(Get-WpaPropertyValue $_ 'reason' '')}})+@($actions|Sort-Object @{Expression={ $classification=[string](Get-WpaPropertyValue $_ 'classification' 'unknown');$risk=[string](Get-WpaPropertyValue $_ 'risk' 'low');if($classification -eq 'unknown'){1}elseif($risk -eq 'high'){2}else{$order[$classification]}}},@{Expression={Get-WpaPropertyValue $_ 'manager' ''}},@{Expression={Get-WpaPropertyValue $_ 'id' ''}})
    foreach($action in $ordered){$verification=Get-WpaPropertyValue $action 'verification';$verificationText=if($verification){(@(Get-WpaPropertyValue $verification 'command' '')+@(Get-WpaPropertyValue $verification 'arguments' @())) -join ' '}else{'-'};$operation=Get-WpaPropertyValue $action 'operation' '-';$source=Get-WpaPropertyValue $action 'source' '-';$target=Get-WpaPropertyValue $action 'targetVersion' '-';$name=Get-WpaPropertyValue $action 'name' '-';$manager=Get-WpaPropertyValue $action 'manager' '-';$id=Get-WpaPropertyValue $action 'id' '-';$classification=Get-WpaPropertyValue $action 'classification' '-';$risk=Get-WpaPropertyValue $action 'risk' '-';$reasonCode=Get-WpaPropertyValue $action 'reasonCode' ''; $reason=Get-WpaPropertyValue $action 'reason' ''; $lines+="| $name | $manager/$id | $source | $classification / $operation | $target | $verificationText | $risk | $reasonCode`: $reason |"}
    if($warnings.Count -gt 0){$lines+='';$lines+='## Warnings';$lines+='';foreach($warning in $warnings){$lines+="- $warning"}}
    return ($lines -join [Environment]::NewLine)+[Environment]::NewLine
}
