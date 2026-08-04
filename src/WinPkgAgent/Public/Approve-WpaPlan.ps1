function Approve-WpaPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$OutputPath)
    if(-not [Environment]::UserInteractive -or [Console]::IsInputRedirected){throw 'Plan approval requires an interactive console controlled by a human.'}
    $plan=Read-WpaJsonFile $PlanPath; Assert-WpaPlanIntegrity $plan | Out-Null
    $expires=[datetimeoffset]::Parse($plan.expiresAt,[Globalization.CultureInfo]::InvariantCulture)
    if([datetimeoffset]::UtcNow -gt $expires){throw 'The plan has expired.'}
    Write-Host (ConvertTo-WpaPlanMarkdown $plan)
    $prefix=$plan.planHash.Substring(0,12)
    $typed=Read-Host "Type the first 12 characters of the plan digest ($prefix)"
    if($typed -cne $prefix){throw 'Digest confirmation did not match.'}
    $now=[datetimeoffset]::UtcNow
    $approval=[pscustomobject][ordered]@{schemaVersion=1;planId=$plan.planId;planHash=$plan.planHash;approvedAt=$now.ToString('o');expiresAt=$expires.ToUniversalTime().ToString('o')}
    Test-WpaDataSchema $approval approval | Out-Null
    if($PSCmdlet.ShouldProcess($OutputPath,'Write separate plan approval artifact')){Write-WpaAtomicJson $OutputPath $approval}
    return $approval
}
