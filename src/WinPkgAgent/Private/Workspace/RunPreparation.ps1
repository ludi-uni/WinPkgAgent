function Read-WpaRunInputSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$PolicyPath
    )

    $manifestText = Read-WpaTextFile -Path $ManifestPath
    $manifestData = ConvertFrom-WpaYamlText -Text $manifestText
    $policyText = Read-WpaTextFile -Path $PolicyPath
    $policy = ConvertFrom-WpaYamlText -Text $policyText
    Test-WpaPolicyObject -Policy $policy | Out-Null
    Test-WpaDataSchema -Data $policy -SchemaName policy | Out-Null

    $manifestDirectory = Split-Path (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path -Parent
    $profileNames = @(Get-WpaPropertyValue -InputObject $manifestData -Name 'profiles' -Default @())
    $profileSnapshots = [System.Collections.Generic.List[object]]::new()
    $packages = [System.Collections.Generic.List[object]]::new()

    foreach ($profileNameValue in $profileNames) {
        $profileName = [string]$profileNameValue
        if ($profileName -cnotmatch '^[a-z0-9][a-z0-9-]{0,31}$') { throw 'Invalid profile name.' }
        $candidates = @(
            [IO.Path]::GetFullPath((Join-Path $manifestDirectory "profiles/$profileName.yaml"))
            [IO.Path]::GetFullPath((Join-Path $manifestDirectory "../profiles/$profileName.yaml"))
            [IO.Path]::GetFullPath((Join-Path $manifestDirectory "../profiles/$profileName.example.yaml"))
        )
        $profilePath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $profilePath) { throw "Profile not found: $profileName" }

        $profileText = Read-WpaTextFile -Path $profilePath
        $profileData = ConvertFrom-WpaYamlText -Text $profileText
        if (@(Get-WpaPropertyValue -InputObject $profileData -Name 'profiles' -Default @()).Count -gt 0) {
            throw 'Nested profiles are not supported.'
        }
        $profileSnapshots.Add([pscustomobject]@{name=$profileName;text=$profileText})
        foreach ($package in @(Get-WpaPropertyValue -InputObject $profileData -Name 'packages' -Default @())) {
            $packages.Add($package)
        }
    }

    foreach ($package in @(Get-WpaPropertyValue -InputObject $manifestData -Name 'packages' -Default @())) {
        $packages.Add($package)
    }
    $resolvedManifest = [pscustomobject][ordered]@{
        schemaVersion = Get-WpaPropertyValue -InputObject $manifestData -Name 'schemaVersion'
        profiles = @($profileNames)
        packages = @($packages)
    }
    Test-WpaManifestObject -Manifest $resolvedManifest | Out-Null
    Test-WpaDataSchema -Data $resolvedManifest -SchemaName manifest | Out-Null

    return [pscustomobject][ordered]@{
        manifestText = $manifestText
        policyText = $policyText
        profiles = @($profileSnapshots)
        manifest = $resolvedManifest
        policy = $policy
    }
}

function Get-WpaRunPreparation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$PolicyPath,
        [Parameter(Mandatory)][string]$RunId,
        [datetimeoffset]$Now = [datetimeoffset]::UtcNow
    )

    if ($RunId -cnotmatch '^[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') { throw 'RUN_ID_INVALID' }
    $snapshot = Read-WpaRunInputSnapshot -ManifestPath $ManifestPath -PolicyPath $PolicyPath
    $environment = Test-WpaEnvironmentForPolicy -Policy $snapshot.policy
    if (-not [bool](Get-WpaPropertyValue -InputObject $environment -Name 'ready' -Default $false)) {
        throw 'PREVIEW_ENVIRONMENT_NOT_READY'
    }
    $inventory = Get-WpaInventoryForPolicy -Policy $snapshot.policy
    $inventoryStatus = [string](Get-WpaPropertyValue -InputObject $inventory -Name 'status' -Default '')
    if ($inventoryStatus -cne 'success') { throw "PREVIEW_INVENTORY_NOT_TRUSTED: $inventoryStatus" }
    $plan = ConvertTo-WpaPlanObject -Manifest $snapshot.manifest -Policy $snapshot.policy -Inventory $inventory -Now $Now
    $run = [pscustomobject][ordered]@{
        schemaVersion = 1
        runId = $RunId
        createdAt = $Now.ToUniversalTime().ToString('o')
        manifestHash = $plan.manifestHash
        policyHash = $plan.policyHash
        manifestPath = 'manifest.yaml'
        policyPath = 'policy.yaml'
        inventoryPath = 'inventory.json'
        planPath = 'plan.json'
        approvalPath = 'approval.json'
        applyResultPath = 'apply-result.json'
        verifyResultPath = 'verify-result.json'
        journalPath = 'journal.json'
        summaryPath = 'summary.md'
        currentStage = 'planned'
    }

    return [pscustomobject][ordered]@{
        manifestText = $snapshot.manifestText
        policyText = $snapshot.policyText
        profiles = @($snapshot.profiles)
        manifest = $snapshot.manifest
        policy = $snapshot.policy
        inventory = $inventory
        plan = $plan
        run = $run
    }
}
