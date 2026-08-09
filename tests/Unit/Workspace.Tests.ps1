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

        It 'initializes run inventory from the copied run-local policy' {
            $manifestPath = Join-Path $TestDrive 'manifest.yaml'
            $policyPath = Join-Path $TestDrive 'source-policy.yaml'
            Set-Content -LiteralPath $manifestPath -Value 'packages: []' -NoNewline
            Set-Content -LiteralPath $policyPath -Value 'schemaVersion: 1' -NoNewline
            $script:inventoryPolicyPath = $null
            Mock Read-WpaYamlFile { [pscustomobject]@{profiles=@()} }
            Mock Get-WpaInventory {
                param([string]$PolicyPath)
                $script:inventoryPolicyPath = $PolicyPath
                [pscustomobject]@{schemaVersion=1;environment=@{id='env'};status='success';managers=@();packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            }
            Mock New-WpaPlan { [pscustomobject]@{manifestHash='manifest';policyHash='policy'} }

            $run = New-WpaRun -ManifestPath $manifestPath -PolicyPath $policyPath -WorkspacePath (Join-Path $TestDrive 'workspace') -Now ([datetimeoffset]'2026-08-08T01:02:03Z')

            $script:inventoryPolicyPath | Should -Be (Get-WpaRunArtifactPath -RunPath (Split-Path $script:inventoryPolicyPath -Parent) -Artifact policy)
            $script:inventoryPolicyPath | Should -Not -Be $policyPath
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
    }
}
