function Resume-WpaVerification {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$ApplyResultPath,[Parameter(Mandatory)][string]$PolicyPath,[string]$VerifyOutputPath='./artifacts/verify-result.json')
    $plan=Read-WpaJsonFile $PlanPath;Test-WpaDataSchema $plan plan|Out-Null
    $apply=Read-WpaJsonFile $ApplyResultPath;Test-WpaDataSchema $apply apply-result|Out-Null
    if($plan.planId -ne $apply.planId){throw 'Plan and apply result do not belong to the same run.'}
    if(-not [bool]$apply.rebootRequired -and @($apply.operations|Where-Object reasonCode -eq 'REBOOT_REQUIRED').Count -eq 0){throw 'Apply result does not require resumed verification.'}
    $inventory=Get-WpaInventory -PolicyPath $PolicyPath;$items=@()
    foreach($result in @($apply.operations|Where-Object status -eq completed)){
        $action=@($plan.actions|Where-Object {$_.manager -eq $result.manager -and $_.id -eq $result.id}|Select-Object -First 1)
        if($action.Count -eq 0){throw "Apply result operation is not present in the plan: $($result.manager)/$($result.id)"}
        $items+=Test-WpaExpectedState -Action $action[0] -Inventory $inventory
    }
    $status=if(@($items|Where-Object status -eq 'verification-failed').Count -gt 0){'failed'}elseif(@($items|Where-Object status -eq 'indeterminate').Count -gt 0){'indeterminate'}else{'success'}
    $verify=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;status=$status;verifiedAt=[datetimeoffset]::UtcNow.ToString('o');items=@($items);rebootRequired=$false}
    Test-WpaDataSchema $verify verify-result|Out-Null;if($PSCmdlet.ShouldProcess($VerifyOutputPath,'Write resumed verification result')){Write-WpaAtomicJson $VerifyOutputPath $verify};$verify
}
