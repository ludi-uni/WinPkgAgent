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
    $actions=@($Plan.actions);$blocked=@($Plan.blockedOperations);$unknown=@($actions|Where-Object {$_.classification -eq 'unknown' -or $_.reasonCode -match 'UNKNOWN'});$high=@($actions|Where-Object {$_.risk -eq 'high'});$reboot=@($actions|Where-Object {$_.rebootRequired -eq $true -or $_.reasonCode -match 'REBOOT'})
    $lines=@('# winpkg-agent plan','',"Plan ID: $($Plan.planId)","Expires: $($Plan.expiresAt)","Changes: $($actions.Count)","Blocked: $($blocked.Count)","Unknown: $($unknown.Count)","High risk: $($high.Count)","Reboot possible: $(if($reboot.Count -gt 0){'yes'}else{'no'})",'','## Actions','','| Package | Manager ID | Source | Classification / operation | Target | Verification | Risk | Reason |','|---|---|---|---|---|---|---|---|')
    $order=@{'blockedOperations'=0;'unknown'=1;'high'=2;'upgrade'=3;'install'=4;'unmanaged'=5;'no-op'=6}
    $ordered=@($blocked|ForEach-Object {[pscustomobject]@{name=$_.name;manager=$_.manager;id=$_.id;source=$_.source;classification='blocked';operation=$_.operation;targetVersion=$_.targetVersion;verification=$_.verification;risk=$_.risk;reasonCode=$_.reasonCode;reason=$_.reason}})+@($actions|Sort-Object @{Expression={if($_.classification -eq 'unknown'){1}elseif($_.risk -eq 'high'){2}else{$order[[string]$_.classification]}}},manager,id)
    foreach($action in $ordered){$verification=Get-WpaPropertyValue $action 'verification';$verificationText=if($verification){(@($verification.command)+@($verification.arguments)) -join ' '}else{'-'};$operation=Get-WpaPropertyValue $action 'operation' '-';$source=Get-WpaPropertyValue $action 'source' '-';$target=Get-WpaPropertyValue $action 'targetVersion' '-';$lines+="| $($action.name) | $($action.manager)/$($action.id) | $source | $($action.classification) / $operation | $target | $verificationText | $($action.risk) | $($action.reasonCode): $($action.reason) |"}
    if(@($Plan.warnings).Count -gt 0){$lines+='';$lines+='## Warnings';$lines+='';foreach($warning in $Plan.warnings){$lines+="- $warning"}}
    return ($lines -join [Environment]::NewLine)+[Environment]::NewLine
}
