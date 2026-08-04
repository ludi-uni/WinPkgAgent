function Show-WpaPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PlanPath)
    $plan=Read-WpaJsonFile $PlanPath; Test-WpaDataSchema $plan plan | Out-Null; Assert-WpaPlanActionSet -Actions @($plan.actions) | Out-Null; Assert-WpaPlanIntegrity $plan | Out-Null
    ConvertTo-WpaPlanMarkdown $plan
}
