function Get-WpaInventoryForPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Policy)

    Test-WpaDataSchema -Data $Policy -SchemaName policy | Out-Null
    $policyHash = Get-WpaObjectHash -InputObject $Policy
    $inventory = Get-WpaInventoryAggregate -Managers @($Policy.allowedManagers | ForEach-Object { [string]$_ }) -PolicyHash $policyHash
    Test-WpaDataSchema -Data $inventory -SchemaName inventory | Out-Null
    return $inventory
}
