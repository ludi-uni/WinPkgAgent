function Test-WpaPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PlanPath,[string]$ApprovalPath,[switch]$CheckEnvironment)
    $errors=[System.Collections.Generic.List[string]]::new()
    try {
        $plan=Read-WpaJsonFile $PlanPath; Test-WpaDataSchema $plan plan | Out-Null; Assert-WpaPlanActionSet -Actions @($plan.actions) | Out-Null; Assert-WpaPlanIntegrity $plan | Out-Null
        if([datetimeoffset]::UtcNow -gt [datetimeoffset]::Parse($plan.expiresAt,[Globalization.CultureInfo]::InvariantCulture)){$errors.Add('PLAN_EXPIRED')}
        if($CheckEnvironment -and $plan.environmentId -ne (Get-WpaEnvironmentId)){$errors.Add('ENVIRONMENT_MISMATCH')}
        if($ApprovalPath){$approval=Read-WpaJsonFile $ApprovalPath;Test-WpaDataSchema $approval approval|Out-Null;Assert-WpaApproval $approval $plan.planId $plan.planHash|Out-Null}
    } catch {$errors.Add($_.Exception.Message)}
    [pscustomobject]@{valid=($errors.Count -eq 0);errors=@($errors)}
}
