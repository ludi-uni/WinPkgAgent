function Get-WpaInventory {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$PolicyPath,
        [string]$OutputPath
    )
    $policy=Read-WpaPolicyFile -Path $PolicyPath
    $inventory=Get-WpaInventoryForPolicy -Policy $policy
    if($OutputPath -and $PSCmdlet.ShouldProcess($OutputPath,'Write inventory artifact')){Write-WpaAtomicJson -Path $OutputPath -Data $inventory}
    return $inventory
}
