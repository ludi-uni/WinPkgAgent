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

function Assert-WpaTrustedPublicationAncestry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspacePath,
        [Parameter(Mandatory)][string]$RunsPath,
        [Parameter(Mandatory)][string]$StagingPath,
        [switch]$StagingMustExist
    )

    try {
        $workspaceFull = [IO.Path]::GetFullPath($WorkspacePath)
        $runsFull = [IO.Path]::GetFullPath($RunsPath)
        $stagingFull = [IO.Path]::GetFullPath($StagingPath)
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($runsFull), $workspaceFull, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals([IO.Path]::GetDirectoryName($stagingFull), $runsFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'lexical ancestry mismatch'
        }
        $resolvedWorkspace = Resolve-WpaTrustedWorkspacePath -WorkspacePath $workspaceFull
        if (-not [string]::Equals($resolvedWorkspace, $workspaceFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'workspace resolution mismatch'
        }
        $runsExists = Test-Path -LiteralPath $runsFull -ErrorAction Stop
        if (-not $runsExists) {
            if ($StagingMustExist) { throw 'runs path missing' }
            return $true
        }
        $runsItem = Get-Item -LiteralPath $runsFull -Force -ErrorAction Stop
        if (-not $runsItem.PSIsContainer -or ($runsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::Equals($runsItem.Parent.FullName, $workspaceFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'runs ancestry untrusted'
        }
        $stagingExists = Test-Path -LiteralPath $stagingFull -ErrorAction Stop
        if (-not $stagingExists) {
            if ($StagingMustExist) { throw 'staging path missing' }
            return $true
        }
        $stagingItem = Get-Item -LiteralPath $stagingFull -Force -ErrorAction Stop
        if (-not $stagingItem.PSIsContainer -or ($stagingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::Equals($stagingItem.Parent.FullName, $runsItem.FullName, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'staging ancestry untrusted'
        }
    } catch {
        throw 'Run publication ancestry is not trusted.'
    }
    return $true
}

function Test-WpaStagingOwnershipIdentity {
    [CmdletBinding()]
    param([AllowNull()][object]$Ownership)

    try {
        if ($null -eq $Ownership -or $null -eq $Ownership.Stream -or -not $Ownership.Stream.CanRead) { return $false }
        $stagingFull = [IO.Path]::GetFullPath([string]$Ownership.StagingPath)
        $runsFull = [IO.Path]::GetFullPath([string]$Ownership.RunsPath)
        $markerFull = [IO.Path]::GetFullPath([string]$Ownership.MarkerPath)
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($stagingFull), $runsFull, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals([IO.Path]::GetFileName($stagingFull), [string]$Ownership.ExpectedLeaf, [StringComparison]::Ordinal) -or
            -not [string]::Equals($markerFull, (Join-Path $stagingFull '.wpa-staging-owner'), [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        $position = $Ownership.Stream.Position
        $Ownership.Stream.Position = 0
        $buffer = [byte[]]::new(128)
        $read = $Ownership.Stream.Read($buffer, 0, $buffer.Length)
        $Ownership.Stream.Position = $position
        $token = [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        if (-not [string]::Equals($token, [string]$Ownership.Token, [StringComparison]::Ordinal)) { return $false }
        $markerItem = Get-Item -LiteralPath $markerFull -Force -ErrorAction Stop
        if ($markerItem.PSIsContainer -or ($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
    } catch {
        return $false
    }
    return $true
}

function Assert-WpaOwnedRunStagingTrust {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership)

    if (-not (Test-WpaStagingOwnershipIdentity -Ownership $Ownership)) {
        throw 'Run staging ownership proof is not valid.'
    }
    Assert-WpaTrustedPublicationAncestry -WorkspacePath $Ownership.WorkspacePath -RunsPath $Ownership.RunsPath -StagingPath $Ownership.StagingPath -StagingMustExist | Out-Null
    return $true
}

function New-WpaRunStagingOwnership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspacePath,
        [Parameter(Mandatory)][string]$RunsPath,
        [Parameter(Mandatory)][string]$StagingPath,
        [Parameter(Mandatory)][string]$ExpectedLeaf
    )

    $workspaceFull = [IO.Path]::GetFullPath($WorkspacePath)
    $runsFull = [IO.Path]::GetFullPath($RunsPath)
    $stagingFull = [IO.Path]::GetFullPath($StagingPath)
    Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspaceFull -RunsPath $runsFull -StagingPath $stagingFull | Out-Null
    if (Test-Path -LiteralPath $stagingFull -ErrorAction Stop) { throw 'Run staging workspace already exists.' }

    $stream = $null
    try {
        [IO.Directory]::CreateDirectory($stagingFull) | Out-Null
        Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspaceFull -RunsPath $runsFull -StagingPath $stagingFull -StagingMustExist | Out-Null
        $markerPath = Join-Path $stagingFull '.wpa-staging-owner'
        $token = [guid]::NewGuid().ToString('N')
        $stream = [IO.FileStream]::new(
            $markerPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None,
            4096,
            [IO.FileOptions]::DeleteOnClose
        )
        $bytes = [Text.Encoding]::UTF8.GetBytes($token)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
        $entries = @(Get-ChildItem -LiteralPath $stagingFull -Force -ErrorAction Stop)
        if ($entries.Count -ne 1 -or -not [string]::Equals($entries[0].FullName, $markerPath, [StringComparison]::OrdinalIgnoreCase) -or
            $entries[0].PSIsContainer -or ($entries[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'staging was not empty at ownership acquisition'
        }
        $ownership = [pscustomobject]@{
            WorkspacePath = $workspaceFull
            RunsPath = $runsFull
            StagingPath = $stagingFull
            ExpectedLeaf = $ExpectedLeaf
            MarkerPath = $markerPath
            Token = $token
            Stream = $stream
            OwnedFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            OwnedDirectories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        }
        return $ownership
    } catch {
        if ($null -ne $stream) { $stream.Dispose() }
        throw 'PREVIEW_STAGING_OWNERSHIP_NOT_ACQUIRED'
    }
}

function Write-WpaOwnedStagingText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $fullPath -ErrorAction Stop) { throw 'Owned staging target already exists.' }
    Write-WpaAtomicText -Path $fullPath -Text $Text
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Owned staging target is not trusted.' }
    $Ownership.OwnedFiles.Add($fullPath) | Out-Null
}

function Write-WpaOwnedStagingJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object]$Data)

    Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $fullPath -ErrorAction Stop) { throw 'Owned staging target already exists.' }
    Write-WpaAtomicJson -Path $fullPath -Data $Data
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Owned staging target is not trusted.' }
    $Ownership.OwnedFiles.Add($fullPath) | Out-Null
}

function Assert-WpaOwnedStagingContents {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership,[switch]$OwnershipReleased)

    if ($OwnershipReleased) {
        Assert-WpaTrustedPublicationAncestry -WorkspacePath $Ownership.WorkspacePath -RunsPath $Ownership.RunsPath -StagingPath $Ownership.StagingPath -StagingMustExist | Out-Null
    } else {
        Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
    }
    $seenFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $seenDirectories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @(Get-ChildItem -LiteralPath $Ownership.StagingPath -Force -ErrorAction Stop)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Unowned staging content detected.' }
        if ([string]::Equals($entry.FullName, $Ownership.MarkerPath, [StringComparison]::OrdinalIgnoreCase)) {
            if ($OwnershipReleased) { throw 'Released ownership marker remains.' }
            continue
        }
        if ($entry.PSIsContainer) {
            if (-not $Ownership.OwnedDirectories.Contains($entry.FullName)) { throw 'Unowned staging content detected.' }
            $seenDirectories.Add($entry.FullName) | Out-Null
            foreach ($child in @(Get-ChildItem -LiteralPath $entry.FullName -Force -ErrorAction Stop)) {
                if ($child.PSIsContainer -or ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    -not $Ownership.OwnedFiles.Contains($child.FullName)) { throw 'Unowned staging content detected.' }
                $seenFiles.Add($child.FullName) | Out-Null
            }
        } else {
            if (-not $Ownership.OwnedFiles.Contains($entry.FullName)) { throw 'Unowned staging content detected.' }
            $seenFiles.Add($entry.FullName) | Out-Null
        }
    }
    if ($seenFiles.Count -ne $Ownership.OwnedFiles.Count -or $seenDirectories.Count -ne $Ownership.OwnedDirectories.Count) {
        throw 'Owned staging content changed unexpectedly.'
    }
    return $true
}

function Remove-WpaOwnedRunStagingDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Ownership)

    if (-not (Test-WpaStagingOwnershipIdentity -Ownership $Ownership)) {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: OWNERSHIP_NOT_PROVEN'
    }
    try {
        Assert-WpaTrustedPublicationAncestry -WorkspacePath $Ownership.WorkspacePath -RunsPath $Ownership.RunsPath -StagingPath $Ownership.StagingPath -StagingMustExist | Out-Null
    } catch {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: UNTRUSTED_ANCESTRY'
    }
    try {
        Assert-WpaOwnedStagingContents -Ownership $Ownership | Out-Null
    } catch {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: UNKNOWN_CONTENT'
    }

    foreach ($ownedFile in @($Ownership.OwnedFiles | Sort-Object Length -Descending)) {
        try {
            Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
            $item = Get-Item -LiteralPath $ownedFile -Force -ErrorAction Stop
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'owned file untrusted' }
            Remove-Item -LiteralPath $ownedFile -Force -ErrorAction Stop
        } catch {
            throw 'PREVIEW_STAGING_CLEANUP_FAILED: DELETE_FAILED'
        }
    }
    foreach ($ownedDirectory in @($Ownership.OwnedDirectories | Sort-Object Length -Descending)) {
        try {
            Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
            $item = Get-Item -LiteralPath $ownedDirectory -Force -ErrorAction Stop
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                @(Get-ChildItem -LiteralPath $ownedDirectory -Force -ErrorAction Stop).Count -ne 0) { throw 'owned directory untrusted' }
            [IO.Directory]::Delete($ownedDirectory, $false)
        } catch {
            throw 'PREVIEW_STAGING_CLEANUP_FAILED: DELETE_FAILED'
        }
    }

    try {
        Assert-WpaOwnedRunStagingTrust -Ownership $Ownership | Out-Null
        $Ownership.Stream.Dispose()
        $Ownership.Stream = $null
        if ([IO.File]::Exists($Ownership.MarkerPath)) { throw 'marker remains' }
        Assert-WpaTrustedPublicationAncestry -WorkspacePath $Ownership.WorkspacePath -RunsPath $Ownership.RunsPath -StagingPath $Ownership.StagingPath -StagingMustExist | Out-Null
        if (@(Get-ChildItem -LiteralPath $Ownership.StagingPath -Force -ErrorAction Stop).Count -ne 0) {
            throw 'unowned content appeared'
        }
        [IO.Directory]::Delete($Ownership.StagingPath, $false)
    } catch {
        throw 'PREVIEW_STAGING_CLEANUP_FAILED: DELETE_FAILED'
    }
}

function Invoke-WpaStagedPlanActionSetValidation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actions)

    try {
        Assert-WpaPlanActionSet -Actions $Actions | Out-Null
    } catch {
        if ($Actions.Count -ne 0 -or $_.FullyQualifiedErrorId -notlike 'ParameterArgumentValidationErrorEmptyArrayNotAllowed*') { throw }
    }
}

function Publish-WpaPreparedRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Preparation,[Parameter(Mandatory)][string]$WorkspacePath)

    $runId = [string](Get-WpaPropertyValue -InputObject $Preparation.run -Name 'runId' -Default '')
    if ($runId -cnotmatch '^[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') { throw 'RUN_ID_INVALID' }
    $workspace = Resolve-WpaTrustedWorkspacePath -WorkspacePath $WorkspacePath
    $runsPath = [IO.Path]::GetFullPath((Join-Path $workspace 'runs'))
    $finalPath = [IO.Path]::GetFullPath((Join-Path $runsPath $runId))
    $stagingLeaf = ".staging-$runId"
    $stagingPath = [IO.Path]::GetFullPath((Join-Path $runsPath $stagingLeaf))
    Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspace -RunsPath $runsPath -StagingPath $stagingPath | Out-Null
    if (Test-Path -LiteralPath $finalPath -ErrorAction Stop) { throw 'Final run workspace already exists.' }
    if (Test-Path -LiteralPath $stagingPath -ErrorAction Stop) { throw 'Run staging workspace already exists.' }

    $profilesPath = [IO.Path]::GetFullPath((Join-Path $stagingPath 'profiles'))
    $profileWrites = [System.Collections.Generic.List[object]]::new()
    foreach ($profile in @(Get-WpaPropertyValue -InputObject $Preparation -Name 'profiles' -Default @())) {
        $profileName = [string](Get-WpaPropertyValue -InputObject $profile -Name 'name' -Default '')
        if ($profileName -cnotmatch '^[a-z0-9][a-z0-9-]{0,31}$') { throw 'Invalid profile name.' }
        $profilePath = [IO.Path]::GetFullPath((Join-Path $profilesPath "$profileName.yaml"))
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($profilePath), $profilesPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Profile path escapes the staging directory.'
        }
        $profileWrites.Add([pscustomobject]@{Path=$profilePath;Text=[string](Get-WpaPropertyValue -InputObject $profile -Name 'text' -Default '')})
    }

    $ownership = $null
    $published = $false
    try {
        $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runsPath -StagingPath $stagingPath -ExpectedLeaf $stagingLeaf
        Write-WpaOwnedStagingText -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath manifest) -Text $Preparation.manifestText
        Write-WpaOwnedStagingText -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath policy) -Text $Preparation.policyText
        Write-WpaOwnedStagingJson -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath inventory) -Data $Preparation.inventory
        Write-WpaOwnedStagingJson -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath plan) -Data $Preparation.plan
        Write-WpaOwnedStagingText -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath planMarkdown) -Text (ConvertTo-WpaPlanMarkdown $Preparation.plan)
        Write-WpaOwnedStagingJson -Ownership $ownership -Path (Get-WpaRunArtifactPath $stagingPath run) -Data $Preparation.run

        if ($profileWrites.Count -gt 0) {
            Assert-WpaOwnedRunStagingTrust -Ownership $ownership | Out-Null
            [IO.Directory]::CreateDirectory($profilesPath) | Out-Null
            $profilesItem = Get-Item -LiteralPath $profilesPath -Force -ErrorAction Stop
            if (($profilesItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or @(Get-ChildItem -LiteralPath $profilesPath -Force).Count -ne 0) {
                throw 'Profile snapshot directory is not trusted.'
            }
            $ownership.OwnedDirectories.Add($profilesPath) | Out-Null
            foreach ($profileWrite in $profileWrites) {
                Write-WpaOwnedStagingText -Ownership $ownership -Path $profileWrite.Path -Text $profileWrite.Text
            }
        }

        Assert-WpaOwnedRunStagingTrust -Ownership $ownership | Out-Null
        Read-WpaRun -RunPath $stagingPath | Out-Null
        $stagedPlan = Read-WpaJsonFile (Get-WpaRunArtifactPath $stagingPath plan)
        Test-WpaDataSchema -Data $stagedPlan -SchemaName plan | Out-Null
        Invoke-WpaStagedPlanActionSetValidation -Actions @($stagedPlan.actions)
        Assert-WpaPlanIntegrity -Plan $stagedPlan | Out-Null
        Assert-WpaOwnedStagingContents -Ownership $ownership | Out-Null
        $ownership.Stream.Dispose()
        $ownership.Stream = $null
        if ([IO.File]::Exists($ownership.MarkerPath)) { throw 'PREVIEW_STAGING_MARKER_RELEASE_FAILED' }
        Assert-WpaOwnedStagingContents -Ownership $ownership -OwnershipReleased | Out-Null
        [IO.Directory]::Move($stagingPath, $finalPath)
        $published = $true
        return $finalPath
    } catch {
        $publicationError = $_
        if ($null -ne $ownership -and -not $published) {
            try {
                Remove-WpaOwnedRunStagingDirectory -Ownership $ownership
            } catch {
                throw $_.Exception.Message
            }
        }
        throw $publicationError
    } finally {
        if ($null -ne $ownership -and $null -ne $ownership.Stream) { $ownership.Stream.Dispose() }
    }
}
