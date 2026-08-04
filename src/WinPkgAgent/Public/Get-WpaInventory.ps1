function Get-WpaInventory {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$OutputPath)
    $inventory=Get-WpaInventoryAggregate
    Test-WpaDataSchema -Data $inventory -SchemaName inventory | Out-Null
    if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Write inventory artifact')){Write-WpaAtomicJson -Path $OutputPath -Data $inventory}
    return $inventory
}
