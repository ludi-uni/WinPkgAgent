function Get-WpaInventory {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$PolicyPath,
        [string]$OutputPath
    )
    $policy=Read-WpaPolicyFile -Path $PolicyPath
    Test-WpaDataSchema -Data $policy -SchemaName policy | Out-Null
    $policyHash=Get-WpaObjectHash -InputObject $policy
    $inventory=Get-WpaInventoryAggregate -Managers @($policy.allowedManagers | ForEach-Object {[string]$_}) -PolicyHash $policyHash
    Test-WpaDataSchema -Data $inventory -SchemaName inventory | Out-Null
    if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Write inventory artifact')){Write-WpaAtomicJson -Path $OutputPath -Data $inventory}
    return $inventory
}
