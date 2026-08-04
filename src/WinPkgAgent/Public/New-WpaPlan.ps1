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
    $inventory=Read-WpaJsonFile $InventoryPath; Test-WpaDataSchema $inventory inventory | Out-Null
    $evaluation=Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
    $expires=$Now.AddMinutes([int]$policy.approvalValidityMinutes)
    $plan=[pscustomobject][ordered]@{
        schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt=$Now.ToUniversalTime().ToString('o');expiresAt=$expires.ToUniversalTime().ToString('o')
        environmentId=$inventory.environment.id;manifestHash=(Get-WpaObjectHash $manifest);policyHash=(Get-WpaObjectHash $policy);inventoryHash=(Get-WpaInventoryStateHash $inventory);managerFingerprints=@($inventory.managers | ForEach-Object {[pscustomobject]@{manager=$_.manager;fingerprint=$_.fingerprint}})
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
    $lines=@('# winpkg-agent plan','',"- Plan ID: $($Plan.planId)","- Content digest: $($Plan.contentHash)","- Plan digest: $($Plan.planHash)","- Expires: $($Plan.expiresAt)",'','## Actions','','| Package | Manager ID | Source | Classification / operation | Target | Verification | Risk | Reason |','|---|---|---|---|---|---|---|---|')
    foreach($action in @($Plan.actions)){$verification=Get-WpaPropertyValue $action 'verification';$verificationText=if($verification){(@($verification.command)+@($verification.arguments)) -join ' '}else{'-'};$operation=Get-WpaPropertyValue $action 'operation' '-';$source=Get-WpaPropertyValue $action 'source' '-';$target=Get-WpaPropertyValue $action 'targetVersion' '-';$lines+="| $($action.name) | $($action.manager)/$($action.id) | $source | $($action.classification) / $operation | $target | $verificationText | $($action.risk) | $($action.reasonCode): $($action.reason) |"}
    if(@($Plan.warnings).Count -gt 0){$lines+='';$lines+='## Warnings';$lines+='';foreach($warning in $Plan.warnings){$lines+="- $warning"}}
    return ($lines -join [Environment]::NewLine)+[Environment]::NewLine
}
