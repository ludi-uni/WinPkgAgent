function Export-WpaUnmanagedCandidate {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$InventoryPath,[Parameter(Mandatory)][string]$OutputPath)
    $inventory = Read-WpaJsonFile -Path $InventoryPath
    Test-WpaDataSchema -Data $inventory -SchemaName inventory | Out-Null
    $knownIds = @($inventory.packages | ForEach-Object { [string]$_.id } | Where-Object { $_ })
    $observationResult = Get-WpaWingetUnmanagedObservation -KnownIds $knownIds
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($warning in @($inventory.warnings)) { if ($warning) { $warnings.Add([string]$warning) } }
    if ($inventory.status -ne 'success') { $warnings.Add('source inventory is not fully successful; known-ID exclusion may be incomplete') }
    if ($observationResult.warning) { $warnings.Add([string]$observationResult.warning) }
    $status = if ($observationResult.status -eq 'failed') { 'failed' } elseif ($inventory.status -ne 'success') { [string]$inventory.status } else { 'success' }
    $artifact = [pscustomobject][ordered]@{
        schemaVersion = 1
        status = $status
        observedAt = (Get-Date).ToUniversalTime().ToString('o')
        inventoryStateHash = Get-WpaInventoryStateHash -Inventory $inventory
        reviewStatus = 'pending'
        warnings = @($warnings)
        observations = @($observationResult.observations)
    }
    Test-WpaDataSchema -Data $artifact -SchemaName 'unmanaged-candidate' | Out-Null
    if ($PSCmdlet.ShouldProcess($OutputPath,'Write unmanaged package review artifact')) { Write-WpaAtomicJson -Path $OutputPath -Data $artifact }
    [pscustomobject]@{ status=$artifact.status; path=$OutputPath; count=@($artifact.observations).Count; reviewStatus='pending' }
}
