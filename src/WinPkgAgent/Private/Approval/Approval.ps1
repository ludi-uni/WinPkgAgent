function Assert-WpaApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Approval,[Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string]$PlanHash,[datetimeoffset]$Now=[datetimeoffset]::UtcNow
    )
    if($Approval.schemaVersion -ne 1){throw 'Unsupported approval schemaVersion.'}
    if($Approval.planId -ne $PlanId){throw 'Approval plan ID mismatch.'}
    if($Approval.planHash -ne $PlanHash){throw 'Approval digest mismatch.'}
    $approved=[datetimeoffset]::Parse($Approval.approvedAt,[Globalization.CultureInfo]::InvariantCulture)
    $expires=[datetimeoffset]::Parse($Approval.expiresAt,[Globalization.CultureInfo]::InvariantCulture)
    if($expires -le $approved -or $Now -gt $expires){throw 'Approval has expired or has an invalid validity interval.'}
    return $true
}
