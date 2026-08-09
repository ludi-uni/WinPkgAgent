$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent run workspace boundaries' {
    InModuleScope WinPkgAgent {
        It 'maps only fixed artifact names inside the run directory' {
            $run=Join-Path $TestDrive 'runs/20260805-010203-aabbccdd';[IO.Directory]::CreateDirectory($run)|Out-Null
            $path=Get-WpaRunArtifactPath $run plan
            $runFull=[IO.Path]::GetFullPath($run)
            $pathFull=[IO.Path]::GetFullPath($path)
            [IO.Path]::GetRelativePath($runFull,$pathFull) | Should -Be 'plan.json'
            [IO.DirectoryInfo]::new((Split-Path -Parent $pathFull)).FullName | Should -Be ([IO.DirectoryInfo]::new($runFull)).FullName
            [IO.Path]::IsPathFullyQualified([IO.Path]::GetRelativePath($runFull,$pathFull)) | Should -BeFalse
        }

        It 'rejects run metadata that points outside the run directory' {
            $run=Join-Path $TestDrive 'run';[IO.Directory]::CreateDirectory($run)|Out-Null
            $metadata=[pscustomobject]@{schemaVersion=1;runId='20260805-010203-aabbccdd';manifestPath='../outside.yaml'}
            Write-WpaAtomicJson (Join-Path $run 'run.json') $metadata
            { Read-WpaRun $run } | Should -Throw
        }

        It 'rejects run paths containing reparse points' {
            $run=Join-Path $TestDrive 'reparse-run';[IO.Directory]::CreateDirectory($run)|Out-Null
            Mock Get-Item { [pscustomobject]@{Attributes=[IO.FileAttributes]::ReparsePoint} }
            { Get-WpaRunArtifactPath $run plan } | Should -Throw '*reparse*'
        }

        It 'exports the new high-level commands without approval bypasses' {
            (Get-Command New-WpaRun,Invoke-WpaRun,Resume-WpaVerification,Initialize-WpaProject,Export-WpaManifestCandidate).Count | Should -Be 5
            (Get-Command Invoke-WpaPlan).Parameters.Keys | Should -Not -Contain 'Force'
        }

        It 'forwards the explicit policy path when resuming verification' {
            $script:inventoryPolicyPath = $null
            $plan = [pscustomobject]@{planId='plan-1';actions=@([pscustomobject]@{manager='scoop';id='tool'})}
            $apply = [pscustomobject]@{planId='plan-1';rebootRequired=$true;operations=@([pscustomobject]@{manager='scoop';id='tool';status='completed'})}
            $inventory = [pscustomobject]@{schemaVersion=2;policyHash=('a' * 64);managerScope=@();environment=@{id='env'};status='success';managers=@();packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaJsonFile { param([string]$Path) if($Path -eq 'plan.json'){$plan}else{$apply} }
            Mock Test-WpaDataSchema { $true }
            Mock Get-WpaInventory { param([string]$PolicyPath) $script:inventoryPolicyPath = $PolicyPath; $inventory }
            Mock Test-WpaExpectedState { [pscustomobject]@{status='verified';reasonCode='EXPECTED_STATE_PRESENT'} }
            Mock Write-WpaAtomicJson {}

            Resume-WpaVerification -PlanPath plan.json -ApplyResultPath apply.json -PolicyPath explicit-policy.yaml -VerifyOutputPath $null -WhatIf

            $script:inventoryPolicyPath | Should -Be 'explicit-policy.yaml'
        }

        Context 'trusted run preparation' {
            BeforeEach {
                $inputRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                [IO.Directory]::CreateDirectory($inputRoot) | Out-Null
                $manifestPath = Join-Path $inputRoot 'manifest.yaml'
                $policyPath = Join-Path $inputRoot 'policy.yaml'
                $manifestText = "schemaVersion: 1`nprofiles: []`npackages: []`n"
                $policyText = [string]::Join("`n", @(
                    'schemaVersion: 1'
                    'allowInstall: true'
                    'allowUpgrade:'
                    '  - patch'
                    '  - minor'
                    'allowedManagers:'
                    '  - scoop'
                    'allowedSources:'
                    '  - main'
                    'protectedPackages: []'
                    'dangerousCategories:'
                    '  - driver'
                    '  - bios'
                    '  - uefi'
                    '  - firmware'
                    'allowUninstall: false'
                    'requireApproval: true'
                    'approvalValidityMinutes: 30'
                    'rejectStateChanges: true'
                    'maxOperations: 20'
                    'operationTimeoutSeconds: 600'
                    'rebootHandling: record-only'
                    'unknownVersionHandling: block'
                )) + "`n"
                $utf8 = [Text.UTF8Encoding]::new($false)
                [IO.File]::WriteAllText($manifestPath, $manifestText, $utf8)
                [IO.File]::WriteAllText($policyPath, $policyText, $utf8)
            }

            It 'preserves exact input text and resolves profile packages before manifest packages' {
                $manifestText = "# source manifest`nschemaVersion: 1`nprofiles:`n  - base`npackages:`n  - name: app-tool`n    manager: scoop`n    id: app-tool`n    state: present`n    source: main`n    category: application`n"
                $profileText = "# selected profile`nschemaVersion: 1`nprofiles: []`npackages:`n  - name: base-tool`n    manager: scoop`n    id: base-tool`n    state: present`n    source: main`n    category: cli`n"
                $profileDirectory = Join-Path $inputRoot 'profiles'
                [IO.Directory]::CreateDirectory($profileDirectory) | Out-Null
                [IO.File]::WriteAllText($manifestPath, $manifestText, $utf8)
                [IO.File]::WriteAllText((Join-Path $profileDirectory 'base.yaml'), $profileText, $utf8)

                $snapshot = Read-WpaRunInputSnapshot -ManifestPath $manifestPath -PolicyPath $policyPath

                $snapshot.manifestText | Should -BeExactly $manifestText
                $snapshot.policyText | Should -BeExactly $policyText
                $snapshot.profiles.Count | Should -Be 1
                $snapshot.profiles[0].name | Should -BeExactly 'base'
                $snapshot.profiles[0].text | Should -BeExactly $profileText
                @($snapshot.manifest.packages.name) | Should -Be @('base-tool', 'app-tool')
                @($snapshot.manifest.profiles) | Should -Be @('base')
            }

            It 'rejects an invalid profile name before resolving profile files' {
                $invalidManifestText = "schemaVersion: 1`nprofiles:`n  - Bad_Profile`npackages: []`n"
                [IO.File]::WriteAllText($manifestPath, $invalidManifestText, $utf8)

                { Read-WpaRunInputSnapshot -ManifestPath $manifestPath -PolicyPath $policyPath } |
                    Should -Throw 'Invalid profile name.'
            }

            It 'rejects a selected profile that declares nested profiles' {
                $nestedManifestText = "schemaVersion: 1`nprofiles:`n  - base`npackages: []`n"
                $nestedProfileText = "schemaVersion: 1`nprofiles:`n  - other`npackages: []`n"
                $profileDirectory = Join-Path $inputRoot 'profiles'
                [IO.Directory]::CreateDirectory($profileDirectory) | Out-Null
                [IO.File]::WriteAllText($manifestPath, $nestedManifestText, $utf8)
                [IO.File]::WriteAllText((Join-Path $profileDirectory 'base.yaml'), $nestedProfileText, $utf8)

                { Read-WpaRunInputSnapshot -ManifestPath $manifestPath -PolicyPath $policyPath } |
                    Should -Throw 'Nested profiles are not supported.'
            }

            It 'stops before inventory and planning when the policy environment is not ready' {
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$false} }
                Mock Get-WpaInventoryForPolicy { throw 'INVENTORY_CALL_GUARD' }
                Mock New-WpaPlanObject { throw 'PLAN_CALL_GUARD' }

                Push-Location $TestDrive
                try {
                    { New-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' } |
                        Should -Throw 'PREVIEW_ENVIRONMENT_NOT_READY'
                } finally {
                    Pop-Location
                }

                Should -Invoke Test-WpaEnvironmentForPolicy -Times 1 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
                Should -Invoke New-WpaPlanObject -Times 0 -Exactly
                Test-Path (Join-Path $TestDrive '.wpa') | Should -BeFalse
            }

            It 'rejects partial inventory before planning and leaves no workspace' {
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
                Mock Get-WpaInventoryForPolicy { [pscustomobject]@{status='partial'} }
                Mock New-WpaPlanObject { throw 'PLAN_CALL_GUARD' }

                Push-Location $TestDrive
                try {
                    { New-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' } |
                        Should -Throw 'PREVIEW_INVENTORY_NOT_TRUSTED: partial'
                } finally {
                    Pop-Location
                }

                Should -Invoke Get-WpaInventoryForPolicy -Times 1 -Exactly
                Should -Invoke New-WpaPlanObject -Times 0 -Exactly
                Test-Path (Join-Path $TestDrive '.wpa') | Should -BeFalse
            }

            It 'rejects failed inventory before planning and leaves no workspace' {
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
                Mock Get-WpaInventoryForPolicy { [pscustomobject]@{status='failed'} }
                Mock New-WpaPlanObject { throw 'PLAN_CALL_GUARD' }

                Push-Location $TestDrive
                try {
                    { New-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' } |
                        Should -Throw 'PREVIEW_INVENTORY_NOT_TRUSTED: failed'
                } finally {
                    Pop-Location
                }

                Should -Invoke Get-WpaInventoryForPolicy -Times 1 -Exactly
                Should -Invoke New-WpaPlanObject -Times 0 -Exactly
                Test-Path (Join-Path $TestDrive '.wpa') | Should -BeFalse
            }

            It 'passes identical snapshot and inventory objects into one successful plan build' {
                $inventory = [pscustomobject]@{status='success'}
                $plan = [pscustomobject]@{manifestHash=('a' * 64);policyHash=('b' * 64)}
                $now = [datetimeoffset]'2026-08-09T10:02:03+09:00'
                $script:environmentPolicy = $null
                $script:inventoryPolicy = $null
                $script:planManifest = $null
                $script:planPolicy = $null
                $script:planInventory = $null
                $script:planNow = $null
                Mock Test-WpaEnvironmentForPolicy {
                    param($Policy)
                    $script:environmentPolicy = $Policy
                    [pscustomobject]@{ready=$true}
                }
                Mock Get-WpaInventoryForPolicy {
                    param($Policy)
                    $script:inventoryPolicy = $Policy
                    $inventory
                }
                Mock New-WpaPlanObject {
                    param($Manifest, $Policy, $Inventory, $Now)
                    $script:planManifest = $Manifest
                    $script:planPolicy = $Policy
                    $script:planInventory = $Inventory
                    $script:planNow = $Now
                    $plan
                }

                $result = New-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' -Now $now

                [object]::ReferenceEquals($result.policy, $script:environmentPolicy) | Should -BeTrue
                [object]::ReferenceEquals($result.policy, $script:inventoryPolicy) | Should -BeTrue
                [object]::ReferenceEquals($result.policy, $script:planPolicy) | Should -BeTrue
                [object]::ReferenceEquals($result.manifest, $script:planManifest) | Should -BeTrue
                [object]::ReferenceEquals($result.inventory, $script:planInventory) | Should -BeTrue
                [object]::ReferenceEquals($result.inventory, $inventory) | Should -BeTrue
                [object]::ReferenceEquals($result.plan, $plan) | Should -BeTrue
                $script:planNow | Should -Be $now
                $result.manifestText | Should -BeExactly $manifestText
                $result.policyText | Should -BeExactly $policyText
                $result.run.schemaVersion | Should -Be 1
                $result.run.runId | Should -BeExactly '20260809-010203-aabbccdd'
                $result.run.createdAt | Should -BeExactly '2026-08-09T01:02:03.0000000+00:00'
                $result.run.manifestHash | Should -BeExactly ('a' * 64)
                $result.run.policyHash | Should -BeExactly ('b' * 64)
                $result.run.manifestPath | Should -BeExactly 'manifest.yaml'
                $result.run.policyPath | Should -BeExactly 'policy.yaml'
                $result.run.inventoryPath | Should -BeExactly 'inventory.json'
                $result.run.planPath | Should -BeExactly 'plan.json'
                $result.run.approvalPath | Should -BeExactly 'approval.json'
                $result.run.applyResultPath | Should -BeExactly 'apply-result.json'
                $result.run.verifyResultPath | Should -BeExactly 'verify-result.json'
                $result.run.journalPath | Should -BeExactly 'journal.json'
                $result.run.summaryPath | Should -BeExactly 'summary.md'
                $result.run.currentStage | Should -BeExactly 'planned'
                Test-WpaDataSchema -Data $result.run -SchemaName run | Should -BeTrue
                Should -Invoke Test-WpaEnvironmentForPolicy -Times 1 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 1 -Exactly
                Should -Invoke New-WpaPlanObject -Times 1 -Exactly
            }

            It 'rejects a non-lowercase RunId before reading inputs or probing managers' {
                Mock Test-WpaEnvironmentForPolicy { throw 'ENVIRONMENT_CALL_GUARD' }
                Mock Get-WpaInventoryForPolicy { throw 'INVENTORY_CALL_GUARD' }
                Mock New-WpaPlanObject { throw 'PLAN_CALL_GUARD' }
                $missingManifest = Join-Path $TestDrive 'missing-manifest.yaml'
                $missingPolicy = Join-Path $TestDrive 'missing-policy.yaml'

                { New-WpaRunPreparation -ManifestPath $missingManifest -PolicyPath $missingPolicy -RunId '20260809-010203-AABBCCDD' } |
                    Should -Throw 'RUN_ID_INVALID'

                Should -Invoke Test-WpaEnvironmentForPolicy -Times 0 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
                Should -Invoke New-WpaPlanObject -Times 0 -Exactly
            }

            It 'does not call file writers or directory helpers and leaves the TestDrive tree unchanged' {
                $inventory = [pscustomobject]@{status='success'}
                $plan = [pscustomobject]@{manifestHash=('a' * 64);policyHash=('b' * 64)}
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
                Mock Get-WpaInventoryForPolicy { $inventory }
                Mock New-WpaPlanObject { $plan }
                Mock Write-WpaAtomicJson { throw 'FILE_WRITE_GUARD: JSON writer invoked' }
                Mock Write-WpaAtomicText { throw 'FILE_WRITE_GUARD: text writer invoked' }
                Mock New-Item { throw 'DIRECTORY_CREATE_GUARD: New-Item invoked' }
                $before = @(Get-ChildItem -LiteralPath $TestDrive -File -Recurse | Sort-Object FullName | ForEach-Object {
                    '{0}|{1}' -f [IO.Path]::GetRelativePath($TestDrive, $_.FullName), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                })

                Push-Location $TestDrive
                try {
                    $null = New-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd'
                } finally {
                    Pop-Location
                }

                $after = @(Get-ChildItem -LiteralPath $TestDrive -File -Recurse | Sort-Object FullName | ForEach-Object {
                    '{0}|{1}' -f [IO.Path]::GetRelativePath($TestDrive, $_.FullName), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                })
                Compare-Object -ReferenceObject $before -DifferenceObject $after | Should -BeNullOrEmpty
                Test-Path (Join-Path $TestDrive '.wpa') | Should -BeFalse
                Should -Invoke Write-WpaAtomicJson -Times 0 -Exactly
                Should -Invoke Write-WpaAtomicText -Times 0 -Exactly
                Should -Invoke New-Item -Times 0 -Exactly
            }
        }

        Context 'prepared run publication' {
            BeforeEach {
                $script:preparedRun = [pscustomobject][ordered]@{
                    schemaVersion = 1
                    runId = '20260809-010203-aabbccdd'
                    createdAt = '2026-08-09T01:02:03.0000000Z'
                    manifestHash = ('a' * 64)
                    policyHash = ('b' * 64)
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
                $script:preparation = [pscustomobject][ordered]@{
                    manifestText = "schemaVersion: 1`nprofiles:`n  - base`npackages: []`n"
                    policyText = "schemaVersion: 1`n"
                    profiles = @([pscustomobject]@{name='base';text="schemaVersion: 1`nprofiles: []`npackages: []`n"})
                    inventory = [pscustomobject]@{status='success'}
                    plan = [pscustomobject]@{
                        planId = 'plan-1'
                        expiresAt = '2026-08-09T01:32:03.0000000Z'
                        actions = @()
                        blockedOperations = @()
                        warnings = @()
                        planHash = ('c' * 64)
                    }
                    run = $script:preparedRun
                }
                Mock Test-WpaDataSchema { $true }
                Mock Assert-WpaPlanActionSet { $true }
                Mock Assert-WpaPlanIntegrity { $true }
            }

            It 'publishes exact prepared artifacts and returns the unchanged run only after preparation succeeds' {
                Mock New-WpaRunPreparation {
                    param($ManifestPath, $PolicyPath, $RunId, $Now)
                    $script:preparation.run.runId = $RunId
                    $script:preparation
                }
                $workspace = Join-Path $TestDrive 'workspace-published'

                $run = New-WpaRun -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $workspace -Now ([datetimeoffset]'2026-08-08T01:02:03Z')

                [object]::ReferenceEquals($run, $script:preparation.run) | Should -BeTrue
                $final = Join-Path $workspace "runs/$($run.runId)"
                [IO.File]::ReadAllText((Join-Path $final 'manifest.yaml')) | Should -BeExactly $script:preparation.manifestText
                [IO.File]::ReadAllText((Join-Path $final 'policy.yaml')) | Should -BeExactly $script:preparation.policyText
                [IO.File]::ReadAllText((Join-Path $final 'profiles/base.yaml')) | Should -BeExactly $script:preparation.profiles[0].text
                foreach ($artifact in @('run.json','inventory.json','plan.json','plan.md')) {
                    Test-Path (Join-Path $final $artifact) | Should -BeTrue
                }
                foreach ($artifact in @('approval.json','apply-result.json','verify-result.json','journal.json','summary.md')) {
                    Test-Path (Join-Path $final $artifact) | Should -BeFalse
                }
                Test-Path (Join-Path $final '.wpa-staging-owner') | Should -BeFalse
                Get-ChildItem (Join-Path $workspace 'runs') -Directory -Filter '.staging-*' | Should -BeNullOrEmpty
            }

            It 'atomically creates staging and returns the retained owned directory handle' {
                $runs = Join-Path $TestDrive 'atomic-acquisition/runs'
                $staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
                [IO.Directory]::CreateDirectory($runs) | Out-Null

                $handle = New-WpaOwnedDirectoryHandleAtomically -Path $staging
                try {
                    $handle.IsOpen | Should -BeTrue
                    [IO.Directory]::Exists($staging) | Should -BeTrue
                    @(Get-ChildItem -LiteralPath $staging -Force) | Should -BeNullOrEmpty
                } finally {
                    if ($null -ne $handle) { $handle.Dispose() }
                }
            }

            It 'rejects an atomic acquisition collision without changing or deleting the existing directory' {
                $runs = Join-Path $TestDrive 'atomic-collision/runs'
                $staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
                $foreignFile = Join-Path $staging 'foreign.txt'
                [IO.Directory]::CreateDirectory($staging) | Out-Null
                [IO.File]::WriteAllText($foreignFile, 'preserve-collision')
                Mock Remove-Item {}

                { New-WpaOwnedDirectoryHandleAtomically -Path $staging } |
                    Should -Throw 'PREVIEW_STAGING_OWNERSHIP_NOT_ACQUIRED'

                [IO.File]::ReadAllText($foreignFile) | Should -BeExactly 'preserve-collision'
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'fails closed without staging or publication when native atomic acquisition fails' {
                $workspace = Join-Path $TestDrive 'workspace-native-acquisition-failure'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $final = Join-Path $runs $script:preparedRun.runId
                Mock New-WpaOwnedDirectoryHandleAtomically { throw 'PREVIEW_STAGING_OWNERSHIP_NOT_ACQUIRED' }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_OWNERSHIP_NOT_ACQUIRED'

                Test-Path $staging | Should -BeFalse
                Test-Path $final | Should -BeFalse
                Should -Invoke New-WpaOwnedDirectoryHandleAtomically -Times 1 -Exactly
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'leaves no workspace when preparation fails' {
                Mock New-WpaRunPreparation { throw 'simulated preparation failure' }
                $workspace = Join-Path $TestDrive 'workspace-preparation-failure'

                { New-WpaRun -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $workspace } |
                    Should -Throw 'simulated preparation failure'

                Test-Path $workspace | Should -BeFalse
            }

            It 'preserves staging and unrelated content with a fixed sanitized error when publication fails' {
                $workspace = Join-Path $TestDrive 'workspace-publication-failure'
                $runs = Join-Path $workspace 'runs'
                $unrelated = Join-Path $runs '.staging-unrelated'
                [IO.Directory]::CreateDirectory($unrelated) | Out-Null
                [IO.File]::WriteAllText((Join-Path $unrelated 'keep.txt'), 'keep')
                Mock Write-WpaOwnedStagingJson { throw 'simulated publication failure' } -ParameterFilter { $Path -like '*plan.json' }
                Mock Remove-Item {}

                $message = try {
                    Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace
                    ''
                } catch {
                    $_.Exception.Message
                }

                $message | Should -BeExactly 'PREVIEW_STAGING_PRESERVED'
                $message | Should -Not -Match ([regex]::Escape($TestDrive))
                Test-Path (Join-Path $runs $script:preparedRun.runId) | Should -BeFalse
                Test-Path (Join-Path $runs ".staging-$($script:preparedRun.runId)") | Should -BeTrue
                [IO.File]::ReadAllText((Join-Path $unrelated 'keep.txt')) | Should -BeExactly 'keep'
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'refuses a staging directory claimed by a competing exclusive owner and never deletes it' {
                $workspace = Join-Path $TestDrive 'workspace-ownership-race'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $ownerMarker = Join-Path $staging '.wpa-staging-owner'
                $foreignFile = Join-Path $staging 'foreign.txt'
                $script:raceInjected = $false
                $script:stagingProbeCount = 0
                Mock Test-Path {
                    $script:stagingProbeCount++
                    if (-not $script:raceInjected -and $script:stagingProbeCount -eq 2) {
                        $script:raceInjected = $true
                        [IO.Directory]::CreateDirectory($staging) | Out-Null
                        [IO.File]::WriteAllText($ownerMarker, 'foreign-owner-token')
                        [IO.File]::WriteAllText($foreignFile, 'preserve')
                        return $false
                    }
                    [IO.Directory]::Exists($LiteralPath) -or [IO.File]::Exists($LiteralPath)
                } -ParameterFilter { $LiteralPath -eq $staging }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_OWNERSHIP_NOT_ACQUIRED'

                [IO.File]::ReadAllText($ownerMarker) | Should -BeExactly 'foreign-owner-token'
                [IO.File]::ReadAllText($foreignFile) | Should -BeExactly 'preserve'
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'refuses cleanup without removal when runs ancestry becomes a reparse point after ownership' {
                $workspace = Join-Path $TestDrive 'workspace-ancestry-transition'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $ownerMarker = Join-Path $staging '.wpa-staging-owner'
                $firstOwnedArtifact = Join-Path $staging 'manifest.yaml'
                Mock Get-Item {
                    if ([IO.File]::Exists($firstOwnedArtifact)) {
                        return [pscustomobject]@{
                            FullName = $runs
                            PSIsContainer = $true
                            Attributes = [IO.FileAttributes]::ReparsePoint
                            Parent = [pscustomobject]@{FullName=$workspace}
                        }
                    }
                    [pscustomobject]@{
                        FullName = $runs
                        PSIsContainer = $true
                        Attributes = [IO.FileAttributes]::Directory
                        Parent = [pscustomobject]@{FullName=$workspace}
                    }
                } -ParameterFilter { $LiteralPath -eq $runs }
                Mock Write-WpaOwnedStagingJson { throw 'simulated publication failure' } -ParameterFilter { $Path -like '*plan.json' }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                [IO.Directory]::Exists($staging) | Should -BeTrue
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'rejects an existing final path before writing staged artifacts' {
                $workspace = Join-Path $TestDrive 'workspace-existing-final'
                $final = Join-Path $workspace "runs/$($script:preparedRun.runId)"
                [IO.Directory]::CreateDirectory($final) | Out-Null
                [IO.File]::WriteAllText((Join-Path $final 'keep.txt'), 'keep')
                Mock Write-WpaAtomicText { throw 'WRITE_CALLED' }

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw '*already exists*'

                [IO.File]::ReadAllText((Join-Path $final 'keep.txt')) | Should -BeExactly 'keep'
            }

            It 'rejects an existing staging path before writing staged artifacts' {
                $workspace = Join-Path $TestDrive 'workspace-existing-staging'
                $staging = Join-Path $workspace "runs/.staging-$($script:preparedRun.runId)"
                [IO.Directory]::CreateDirectory($staging) | Out-Null
                [IO.File]::WriteAllText((Join-Path $staging 'keep.txt'), 'keep')
                Mock Write-WpaAtomicText { throw 'WRITE_CALLED' }

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw '*already exists*'

                [IO.File]::ReadAllText((Join-Path $staging 'keep.txt')) | Should -BeExactly 'keep'
            }

            It 'validates the staged plan before publishing the final directory' {
                $workspace = Join-Path $TestDrive 'workspace-invalid-plan'
                Mock Assert-WpaPlanIntegrity { throw 'STAGED_PLAN_INVALID' }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                Test-Path (Join-Path $workspace "runs/$($script:preparedRun.runId)") | Should -BeFalse
                Test-Path (Join-Path $workspace "runs/.staging-$($script:preparedRun.runId)") | Should -BeTrue
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'calls the action-set validator exactly once for an empty staged plan before move' {
                $workspace = Join-Path $TestDrive 'workspace-empty-action-validation'
                Mock Invoke-WpaStagedPlanActionSetValidation { throw 'EMPTY_ACTION_SET_VALIDATION_GUARD' }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                Test-Path (Join-Path $workspace "runs/$($script:preparedRun.runId)") | Should -BeFalse
                Test-Path (Join-Path $workspace "runs/.staging-$($script:preparedRun.runId)") | Should -BeTrue
                Should -Invoke Invoke-WpaStagedPlanActionSetValidation -Times 1 -Exactly
                Should -Invoke Assert-WpaPlanIntegrity -Times 0 -Exactly
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'does not overwrite a file inserted at an owned staging target during publication' {
                $workspace = Join-Path $TestDrive 'workspace-target-substitution'
                $staging = Join-Path $workspace "runs/.staging-$($script:preparedRun.runId)"
                $manifestPath = Join-Path $staging 'manifest.yaml'
                $script:targetInserted = $false
                Mock Test-Path {
                    if (-not $script:targetInserted) {
                        $script:targetInserted = $true
                        [IO.File]::WriteAllText($manifestPath, 'foreign-manifest')
                        return $false
                    }
                    [IO.File]::Exists($LiteralPath) -or [IO.Directory]::Exists($LiteralPath)
                } -ParameterFilter { $LiteralPath -eq $manifestPath }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                [IO.File]::ReadAllText($manifestPath) | Should -BeExactly 'foreign-manifest'
                Test-Path (Join-Path $workspace "runs/$($script:preparedRun.runId)") | Should -BeFalse
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'moves the owned directory object and never a deterministic staging-path replacement' {
                $workspace = Join-Path $TestDrive 'workspace-directory-substitution'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $displacedOwned = Join-Path $runs '.displaced-owned'
                $foreignFile = Join-Path $staging 'foreign.txt'
                $script:directorySubstituted = $false
                Mock Assert-WpaStagingOwnershipMarkerReleased {
                    if (-not $script:directorySubstituted) {
                        $script:directorySubstituted = $true
                        [IO.Directory]::Move($staging, $displacedOwned)
                        [IO.Directory]::CreateDirectory($staging) | Out-Null
                        [IO.File]::WriteAllText($foreignFile, 'preserve-replacement')
                    }
                    $true
                }

                $published = Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace

                $published | Should -Be (Join-Path $runs $script:preparedRun.runId)
                [IO.File]::ReadAllText((Join-Path $published 'manifest.yaml')) | Should -BeExactly $script:preparation.manifestText
                Test-Path (Join-Path $published 'foreign.txt') | Should -BeFalse
                [IO.File]::ReadAllText($foreignFile) | Should -BeExactly 'preserve-replacement'
                Test-Path $displacedOwned | Should -BeFalse
                Should -Invoke Assert-WpaStagingOwnershipMarkerReleased -Times 1 -Exactly
            }

            It 'revalidates profile names before creating the staging directory' {
                $workspace = Join-Path $TestDrive 'workspace-invalid-profile'
                $script:preparation.profiles = @([pscustomobject]@{name='Bad_Profile';text='unsafe'})

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'Invalid profile name.'

                Test-Path $workspace | Should -BeFalse
            }

            It 'refuses cleanup when the staging parent is not the owned runs directory' {
                $workspace = Join-Path $TestDrive 'workspace-cleanup-parent'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
                $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runs -StagingPath $staging -ExpectedLeaf '.staging-20260809-010203-aabbccdd'
                $outside = Join-Path $TestDrive '.staging-20260809-010203-aabbccdd'
                [IO.Directory]::CreateDirectory($outside) | Out-Null
                $ownership.StagingPath = $outside

                try {
                    { Remove-WpaOwnedRunStagingDirectory -Ownership $ownership } |
                        Should -Throw 'PREVIEW_STAGING_PRESERVED'
                } finally {
                    if ($null -ne $ownership.Stream) { $ownership.Stream.Dispose() }
                }

                Test-Path $outside | Should -BeTrue
            }

            It 'refuses cleanup when the staging leaf is not the generated leaf' {
                $workspace = Join-Path $TestDrive 'workspace-cleanup-leaf'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
                $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runs -StagingPath $staging -ExpectedLeaf '.staging-20260809-010203-aabbccdd'
                $ownership.ExpectedLeaf = '.staging-other'

                try {
                    { Remove-WpaOwnedRunStagingDirectory -Ownership $ownership } |
                        Should -Throw 'PREVIEW_STAGING_PRESERVED'
                } finally {
                    if ($null -ne $ownership.Stream) { $ownership.Stream.Dispose() }
                }

                Test-Path $staging | Should -BeTrue
            }

            It 'refuses cleanup when the owned staging directory is a reparse point' {
                $workspace = Join-Path $TestDrive 'workspace-cleanup-reparse'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
                $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runs -StagingPath $staging -ExpectedLeaf '.staging-20260809-010203-aabbccdd'
                Mock Get-Item {
                    [pscustomobject]@{FullName=$staging;PSIsContainer=$true;Attributes=[IO.FileAttributes]::ReparsePoint;Parent=[pscustomobject]@{FullName=$runs}}
                } -ParameterFilter { $LiteralPath -eq $staging }
                Mock Remove-Item {}

                try {
                    { Remove-WpaOwnedRunStagingDirectory -Ownership $ownership } |
                        Should -Throw 'PREVIEW_STAGING_PRESERVED'
                } finally {
                    if ($null -ne $ownership.Stream) { $ownership.Stream.Dispose() }
                }

                Test-Path $staging | Should -BeTrue
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'preserves an allowlisted replacement during cleanup and performs zero deletion' {
                $workspace = Join-Path $TestDrive 'workspace-cleanup-replacement'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
                $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runs -StagingPath $staging -ExpectedLeaf '.staging-20260809-010203-aabbccdd'
                $ownedFile = Join-Path $staging 'plan.json'
                [IO.File]::WriteAllText($ownedFile, 'owned')
                $ownership.OwnedFiles.Add([IO.Path]::GetFullPath($ownedFile)) | Out-Null
                [IO.File]::Delete($ownedFile)
                [IO.File]::WriteAllText($ownedFile, 'foreign-replacement')
                Mock Remove-Item {}

                $message = try {
                    Remove-WpaOwnedRunStagingDirectory -Ownership $ownership
                    ''
                } catch {
                    $_.Exception.Message
                } finally {
                    if ($null -ne $ownership.Stream) { $ownership.Stream.Dispose() }
                }

                $message | Should -BeExactly 'PREVIEW_STAGING_PRESERVED'
                $message | Should -Not -Match ([regex]::Escape($TestDrive))
                [IO.File]::ReadAllText($ownedFile) | Should -BeExactly 'foreign-replacement'
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'returns only the future final path on WhatIf for an unavailable drive without provider probes' {
                $usedDrives = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object Name)
                $missingDrive = @('Z','Y','X','W','V','U','T','S','R','Q','P') | Where-Object { $_ -notin $usedDrives } | Select-Object -First 1
                if ([string]::IsNullOrWhiteSpace($missingDrive)) { throw 'No unavailable drive letter is available for the WhatIf test.' }
                $workspace = '{0}:\wpa-whatif-workspace' -f $missingDrive
                $expectedRunsPath = [IO.Path]::Combine([IO.Path]::GetFullPath($workspace), 'runs')
                Mock New-WpaRunPreparation { throw 'PREPARATION_CALLED' }
                Mock Test-WpaEnvironmentForPolicy { throw 'ENVIRONMENT_CALLED' }
                Mock Get-WpaInventoryForPolicy { throw 'INVENTORY_CALLED' }
                Mock Test-WpaWingetAvailable { throw 'WINGET_CALLED' }
                Mock Test-WpaScoopAvailable { throw 'SCOOP_CALLED' }
                Mock Write-WpaAtomicJson { throw 'JSON_WRITE_CALLED' }
                Mock Write-WpaAtomicText { throw 'TEXT_WRITE_CALLED' }
                Mock New-Item { throw 'DIRECTORY_CREATE_CALLED' }
                Mock Resolve-WpaTrustedWorkspacePath { throw 'WORKSPACE_RESOLVER_CALLED' }
                Mock Resolve-Path { throw 'RESOLVE_PATH_CALLED' }
                Mock Test-Path { throw 'TEST_PATH_CALLED' }
                Mock Get-Item { throw 'GET_ITEM_CALLED' }
                Mock Get-ChildItem { throw 'GET_CHILD_ITEM_CALLED' }
                Mock Read-WpaTextFile { throw 'TEXT_READ_CALLED' }
                Mock Read-WpaJsonFile { throw 'JSON_READ_CALLED' }
                Mock Join-Path { throw 'JOIN_PATH_CALLED' }
                Mock New-WpaRunStagingOwnership { throw 'NATIVE_HANDLE_CALLED' }
                Mock New-WpaOwnedDirectoryHandleAtomically { throw 'ATOMIC_NATIVE_HANDLE_CALLED' }

                $result = New-WpaRun -ManifestPath missing-manifest.yaml -PolicyPath missing-policy.yaml -WorkspacePath $workspace -Now ([datetimeoffset]'2026-08-08T01:02:03Z') -WhatIf

                @($result.PSObject.Properties.Name) | Should -Be @('runPath','whatIf')
                $result.whatIf | Should -BeTrue
                [IO.Path]::GetDirectoryName($result.runPath) | Should -Be $expectedRunsPath
                [IO.Path]::GetFileName($result.runPath) | Should -Match '^20260808-010203-[a-f0-9]{8}$'
                [IO.Directory]::Exists($workspace) | Should -BeFalse
                Should -Invoke New-WpaRunPreparation -Times 0 -Exactly
                Should -Invoke Test-WpaEnvironmentForPolicy -Times 0 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
                Should -Invoke Test-WpaWingetAvailable -Times 0 -Exactly
                Should -Invoke Test-WpaScoopAvailable -Times 0 -Exactly
                Should -Invoke Write-WpaAtomicJson -Times 0 -Exactly
                Should -Invoke Write-WpaAtomicText -Times 0 -Exactly
                Should -Invoke New-Item -Times 0 -Exactly
                Should -Invoke Resolve-WpaTrustedWorkspacePath -Times 0 -Exactly
                Should -Invoke Resolve-Path -Times 0 -Exactly
                Should -Invoke Test-Path -Times 0 -Exactly
                Should -Invoke Get-Item -Times 0 -Exactly
                Should -Invoke Get-ChildItem -Times 0 -Exactly
                Should -Invoke Read-WpaTextFile -Times 0 -Exactly
                Should -Invoke Read-WpaJsonFile -Times 0 -Exactly
                Should -Invoke Join-Path -Times 0 -Exactly
                Should -Invoke New-WpaRunStagingOwnership -Times 0 -Exactly
                Should -Invoke New-WpaOwnedDirectoryHandleAtomically -Times 0 -Exactly
            }
        }
    }
}
