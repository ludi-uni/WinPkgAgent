function Resolve-WpaTrustedWorkspacePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspacePath)

    $workspace = [IO.Path]::GetFullPath($WorkspacePath)
    $cursor = $workspace
    while ($cursor) {
        try {
            $exists = Test-Path -LiteralPath $cursor -ErrorAction Stop
            $item = if ($exists) { Get-Item -LiteralPath $cursor -Force -ErrorAction Stop } else { $null }
        } catch {
            throw 'Workspace path state could not be verified.'
        }
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Workspace paths may not contain reparse points.'
        }
        if ($cursor -eq $workspace -and $null -ne $item -and -not $item.PSIsContainer) {
            throw 'Workspace path must be a directory.'
        }
        $next = Split-Path $cursor -Parent
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
    return $workspace
}

function Remove-WpaOwnedRunStagingDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StagingPath,
        [Parameter(Mandatory)][string]$RunsPath,
        [Parameter(Mandatory)][string]$ExpectedLeaf
    )

    try {
        $stagingFull = [IO.Path]::GetFullPath($StagingPath)
        $runsFull = [IO.Path]::GetFullPath($RunsPath)
        $actualParent = [IO.Path]::GetDirectoryName($stagingFull)
        $actualLeaf = [IO.Path]::GetFileName($stagingFull)
    } catch {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: OWNERSHIP_NOT_PROVEN'
    }
    if (-not [string]::Equals($actualParent, $runsFull, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($actualLeaf, $ExpectedLeaf, [StringComparison]::Ordinal)) {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: OWNERSHIP_NOT_PROVEN'
    }

    try {
        if (-not (Test-Path -LiteralPath $stagingFull -ErrorAction Stop)) { return }
        $item = Get-Item -LiteralPath $stagingFull -Force -ErrorAction Stop
    } catch {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: STATE_UNKNOWN'
    }
    if (-not $item.PSIsContainer) {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: STAGING_NOT_DIRECTORY'
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: STAGING_REPARSE_POINT'
    }
    try {
        Remove-Item -LiteralPath $stagingFull -Recurse -Force -ErrorAction Stop
    } catch {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: DELETE_FAILED'
    }
}

function Publish-WpaPreparedRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Preparation,
        [Parameter(Mandatory)][string]$WorkspacePath
    )

    $runId = [string](Get-WpaPropertyValue -InputObject $Preparation.run -Name 'runId' -Default '')
    if ($runId -cnotmatch '^[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') { throw 'RUN_ID_INVALID' }

    $workspace = Resolve-WpaTrustedWorkspacePath -WorkspacePath $WorkspacePath
    $runsPath = [IO.Path]::GetFullPath((Join-Path $workspace 'runs'))
    $finalPath = [IO.Path]::GetFullPath((Join-Path $runsPath $runId))
    $stagingLeaf = ".staging-$runId"
    $stagingPath = [IO.Path]::GetFullPath((Join-Path $runsPath $stagingLeaf))
    if (-not [string]::Equals([IO.Path]::GetDirectoryName($finalPath), $runsPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([IO.Path]::GetDirectoryName($stagingPath), $runsPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Run publication path escapes the runs directory.'
    }

    if (Test-Path -LiteralPath $runsPath -ErrorAction Stop) {
        $runsItem = Get-Item -LiteralPath $runsPath -Force -ErrorAction Stop
        if (-not $runsItem.PSIsContainer -or ($runsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Runs path is not a trusted directory.'
        }
    }
    if (Test-Path -LiteralPath $finalPath -ErrorAction Stop) { throw 'Final run workspace already exists.' }
    if (Test-Path -LiteralPath $stagingPath -ErrorAction Stop) { throw 'Run staging workspace already exists.' }

    $profilesPath = [IO.Path]::GetFullPath((Join-Path $stagingPath 'profiles'))
    $profileWrites = [System.Collections.Generic.List[object]]::new()
    foreach ($profile in @(Get-WpaPropertyValue -InputObject $Preparation -Name 'profiles' -Default @())) {
        $profileName = [string](Get-WpaPropertyValue -InputObject $profile -Name 'name' -Default '')
        if ($profileName -cnotmatch '^[a-z0-9][a-z0-9-]{0,31}$') { throw 'Invalid profile name.' }
        $profilePath = [IO.Path]::GetFullPath((Join-Path $profilesPath "$profileName.yaml"))
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($profilePath), $profilesPath, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals([IO.Path]::GetFileName($profilePath), "$profileName.yaml", [StringComparison]::Ordinal)) {
            throw 'Profile path escapes the staging directory.'
        }
        $profileWrites.Add([pscustomobject]@{Path=$profilePath;Text=[string](Get-WpaPropertyValue -InputObject $profile -Name 'text' -Default '')})
    }

    $stagingCreated = $false
    try {
        $stagingItem = [IO.Directory]::CreateDirectory($stagingPath)
        $stagingCreated = $true
        if (-not [string]::Equals($stagingItem.FullName, $stagingPath, [StringComparison]::OrdinalIgnoreCase) -or
            ($stagingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Run staging workspace is not trusted.'
        }

        Write-WpaAtomicText (Get-WpaRunArtifactPath $stagingPath manifest) $Preparation.manifestText
        Write-WpaAtomicText (Get-WpaRunArtifactPath $stagingPath policy) $Preparation.policyText
        Write-WpaAtomicJson (Get-WpaRunArtifactPath $stagingPath inventory) $Preparation.inventory
        Write-WpaAtomicJson (Get-WpaRunArtifactPath $stagingPath plan) $Preparation.plan
        Write-WpaAtomicText (Get-WpaRunArtifactPath $stagingPath planMarkdown) (ConvertTo-WpaPlanMarkdown $Preparation.plan)
        Write-WpaAtomicJson (Get-WpaRunArtifactPath $stagingPath run) $Preparation.run

        if ($profileWrites.Count -gt 0) {
            $profilesItem = [IO.Directory]::CreateDirectory($profilesPath)
            if (-not [string]::Equals($profilesItem.FullName, $profilesPath, [StringComparison]::OrdinalIgnoreCase) -or
                ($profilesItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Profile snapshot directory is not trusted.'
            }
            foreach ($profileWrite in $profileWrites) {
                if (Test-Path -LiteralPath $profileWrite.Path -ErrorAction Stop) {
                    $profileItem = Get-Item -LiteralPath $profileWrite.Path -Force -ErrorAction Stop
                    if (($profileItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw 'Profile snapshot path may not be a reparse point.'
                    }
                }
                Write-WpaAtomicText $profileWrite.Path $profileWrite.Text
            }
        }

        Read-WpaRun -RunPath $stagingPath | Out-Null
        $stagedPlan = Read-WpaJsonFile (Get-WpaRunArtifactPath $stagingPath plan)
        Test-WpaDataSchema -Data $stagedPlan -SchemaName plan | Out-Null
        $stagedActions = @($stagedPlan.actions)
        if ($stagedActions.Count -gt 0) {
            Assert-WpaPlanActionSet -Actions $stagedActions | Out-Null
        }
        Assert-WpaPlanIntegrity -Plan $stagedPlan | Out-Null
        [IO.Directory]::Move($stagingPath, $finalPath)
        $stagingCreated = $false
        return $finalPath
    } catch {
        $publicationError = $_
        if ($stagingCreated) {
            try {
                Remove-WpaOwnedRunStagingDirectory -StagingPath $stagingPath -RunsPath $runsPath -ExpectedLeaf $stagingLeaf
            } catch {
                throw $_.Exception.Message
            }
        }
        throw $publicationError
    }
}
