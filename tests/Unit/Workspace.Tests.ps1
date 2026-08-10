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

        It 'accepts a legacy run with no publication marker' {
            $run=Join-Path $TestDrive 'legacy-run';[IO.Directory]::CreateDirectory($run)|Out-Null
            $metadata=[pscustomobject]@{schemaVersion=1;runId='20260805-010203-aabbccdd'}
            Mock Read-WpaJsonFile { $metadata }
            Mock Test-WpaDataSchema { $true }

            (Read-WpaRun $run).runId | Should -BeExactly '20260805-010203-aabbccdd'
        }

        It 'rejects a run while its publication marker is pending' {
            $run=Join-Path $TestDrive 'pending-run';[IO.Directory]::CreateDirectory($run)|Out-Null
            [IO.File]::WriteAllText((Join-Path $run '.wpa-publication-pending'),'pending')
            Mock Read-WpaJsonFile { throw 'run metadata must not be read' }

            { Read-WpaRun $run } | Should -Throw 'RUN_PUBLICATION_PENDING'
            Should -Invoke Read-WpaJsonFile -Times 0 -Exactly
        }

        It 'rejects a run while its sibling publication guard is pending' {
            $run=Join-Path $TestDrive 'runs/20260809-010203-aabbccdd';[IO.Directory]::CreateDirectory($run)|Out-Null
            $guard=Join-Path (Split-Path $run -Parent) '.wpa-publication-guard-20260809-010203-aabbccdd'
            [IO.File]::WriteAllText($guard,'pending')
            Mock Read-WpaJsonFile { throw 'run metadata must not be read' }

            { Read-WpaRun $run } | Should -Throw 'RUN_PUBLICATION_PENDING'
            Should -Invoke Read-WpaJsonFile -Times 0 -Exactly
        }

        It 'returns validated run metadata through the workspace reader' {
            $expected = [pscustomobject]@{runId='20260809-010203-aabbccdd';currentStage='planned'}
            Mock Read-WpaRun { $expected }

            $actual = Get-WpaRun -RunPath 'fixture-run'

            [object]::ReferenceEquals($expected, $actual) | Should -BeTrue
        }

        It 'shows the fixed plan artifact and returns the validated run metadata' {
            $runPath = Join-Path $TestDrive 'show-run'
            $expected = [pscustomobject]@{runId='20260809-010203-aabbccdd';currentStage='planned'}
            $script:shownPlanPath = $null
            Mock Read-WpaRun { $expected }
            Mock Show-WpaPlan { param($PlanPath) $script:shownPlanPath = $PlanPath }

            $actual = Show-WpaRun -RunPath $runPath

            [object]::ReferenceEquals($expected, $actual) | Should -BeTrue
            $script:shownPlanPath | Should -BeExactly (Join-Path $runPath 'plan.json')
        }

        It 'persists an allowed run stage only to the fixed run metadata path' {
            $runPath = Join-Path $TestDrive 'stage-run'
            $run = [pscustomobject]@{runId='20260809-010203-aabbccdd';currentStage='planned'}
            $script:stageWritePath = $null
            $script:stageWriteData = $null
            Mock Read-WpaRun { $run }
            Mock Write-WpaAtomicJson { param($Path,$Data) $script:stageWritePath=$Path;$script:stageWriteData=$Data }

            $actual = Set-WpaRunStage -RunPath $runPath -Stage preflighted

            $actual.currentStage | Should -BeExactly 'preflighted'
            $script:stageWritePath | Should -BeExactly (Join-Path $runPath 'run.json')
            [object]::ReferenceEquals($actual, $script:stageWriteData) | Should -BeTrue
        }

        It 'does not persist or report a changed stage when WhatIf declines the write' {
            $runPath = Join-Path $TestDrive 'stage-whatif-run'
            $run = [pscustomobject]@{runId='20260809-010203-aabbccdd';currentStage='planned'}
            Mock Read-WpaRun { $run }
            Mock Write-WpaAtomicJson { throw 'WRITE_GUARD' }

            $actual = Set-WpaRunStage -RunPath $runPath -Stage preflighted -WhatIf

            $actual.currentStage | Should -BeExactly 'planned'
            Should -Invoke Write-WpaAtomicJson -Times 0 -Exactly
        }

        It 'exports the new high-level commands without approval bypasses' {
            (Get-Command New-WpaRun,Invoke-WpaRun,Resume-WpaVerification,Initialize-WpaProject,Export-WpaManifestCandidate).Count | Should -Be 5
            (Get-Command Invoke-WpaPlan).Parameters.Keys | Should -Not -Contain 'Force'
        }

        It 'uses the parsed explicit policy when resuming verification' {
            $script:inventoryPolicy = $null
            $policy = [pscustomobject][ordered]@{schemaVersion=1;allowedManagers=@('scoop')}
            $plan = [pscustomobject]@{planId='plan-1';policyHash=(Get-WpaObjectHash $policy);actions=@([pscustomobject]@{manager='scoop';id='tool'})}
            $apply = [pscustomobject]@{planId='plan-1';rebootRequired=$true;operations=@([pscustomobject]@{manager='scoop';id='tool';status='completed'})}
            $inventory = [pscustomobject]@{schemaVersion=2;policyHash=('a' * 64);managerScope=@();environment=@{id='env'};status='success';managers=@();packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaJsonFile { param([string]$Path) if($Path -eq 'plan.json'){$plan}else{$apply} }
            Mock Read-WpaPolicyFile { $policy }
            Mock Test-WpaDataSchema { $true }
            Mock Get-WpaInventoryForPolicy { param($Policy) $script:inventoryPolicy = $Policy; $inventory }
            Mock Test-WpaExpectedState { [pscustomobject]@{status='verified';reasonCode='EXPECTED_STATE_PRESENT'} }
            Mock Write-WpaAtomicJson {}

            Resume-WpaVerification -PlanPath plan.json -ApplyResultPath apply.json -PolicyPath explicit-policy.yaml -VerifyOutputPath $null -WhatIf

            [object]::ReferenceEquals($policy, $script:inventoryPolicy) | Should -BeTrue
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

            It 'reads each manifest policy and selected profile path exactly once' {
                $manifestText = "schemaVersion: 1`nprofiles:`n  - base`npackages: []`n"
                $profileText = "schemaVersion: 1`nprofiles: []`npackages: []`n"
                $profileDirectory = Join-Path $inputRoot 'profiles'
                $profilePath = Join-Path $profileDirectory 'base.yaml'
                [IO.Directory]::CreateDirectory($profileDirectory) | Out-Null
                [IO.File]::WriteAllText($manifestPath, $manifestText, $utf8)
                [IO.File]::WriteAllText($profilePath, $profileText, $utf8)
                $script:pathReadCounts = @{}
                Mock Read-WpaTextFile {
                    param($Path)
                    $key = [IO.Path]::GetFullPath($Path)
                    $script:pathReadCounts[$key] = 1 + [int]$script:pathReadCounts[$key]
                    [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($key))
                }

                $snapshot = Read-WpaRunInputSnapshot -ManifestPath $manifestPath -PolicyPath $policyPath

                $snapshot.profiles[0].name | Should -BeExactly 'base'
                $script:pathReadCounts[[IO.Path]::GetFullPath($manifestPath)] | Should -Be 1
                $script:pathReadCounts[[IO.Path]::GetFullPath($policyPath)] | Should -Be 1
                $script:pathReadCounts[[IO.Path]::GetFullPath($profilePath)] | Should -Be 1
                $script:pathReadCounts.Count | Should -Be 3
            }

            It 'uses profile candidate precedence and fallbacks' -ForEach @(
                @{ Case='local'; Local=$true; Parent=$true; Example=$true; Expected='local-tool' }
                @{ Case='parent'; Local=$false; Parent=$true; Example=$true; Expected='parent-tool' }
                @{ Case='parent example'; Local=$false; Parent=$false; Example=$true; Expected='example-tool' }
            ) {
                $caseRoot = Join-Path $inputRoot ([guid]::NewGuid().ToString('N'))
                $caseManifestDirectory = Join-Path $caseRoot 'manifest'
                $caseManifestPath = Join-Path $caseManifestDirectory 'manifest.yaml'
                [IO.Directory]::CreateDirectory($caseManifestDirectory) | Out-Null
                $manifestText = "schemaVersion: 1`nprofiles:`n  - base`npackages: []`n"
                [IO.File]::WriteAllText($caseManifestPath, $manifestText, $utf8)
                $localProfiles = Join-Path $caseManifestDirectory 'profiles'
                $parentProfiles = Join-Path $caseRoot 'profiles'
                [IO.Directory]::CreateDirectory($localProfiles) | Out-Null
                [IO.Directory]::CreateDirectory($parentProfiles) | Out-Null
                if ($Local) {
                    [IO.File]::WriteAllText((Join-Path $localProfiles 'base.yaml'), "schemaVersion: 1`nprofiles: []`npackages:`n  - name: local-tool`n    manager: scoop`n    id: local-tool`n    state: present`n    source: main`n    category: cli`n", $utf8)
                }
                if ($Parent) {
                    [IO.File]::WriteAllText((Join-Path $parentProfiles 'base.yaml'), "schemaVersion: 1`nprofiles: []`npackages:`n  - name: parent-tool`n    manager: scoop`n    id: parent-tool`n    state: present`n    source: main`n    category: cli`n", $utf8)
                }
                if ($Example) {
                    [IO.File]::WriteAllText((Join-Path $parentProfiles 'base.example.yaml'), "schemaVersion: 1`nprofiles: []`npackages:`n  - name: example-tool`n    manager: scoop`n    id: example-tool`n    state: present`n    source: main`n    category: cli`n", $utf8)
                }

                $snapshot = Read-WpaRunInputSnapshot -ManifestPath $caseManifestPath -PolicyPath $policyPath

                @($snapshot.manifest.packages.name) | Should -BeExactly @($Expected)
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

            It 'preserves canonical CRLF bytes without a terminal newline in the input snapshot' {
                $manifestText = "schemaVersion: 1`r`nprofiles: []`r`npackages: []"
                $policyText = $policyText.Replace("`n", "`r`n").TrimEnd("`r", "`n")
                $manifestBytes = $utf8.GetBytes($manifestText)
                $policyBytes = $utf8.GetBytes($policyText)
                [IO.File]::WriteAllBytes($manifestPath, $manifestBytes)
                [IO.File]::WriteAllBytes($policyPath, $policyBytes)

                $snapshot = Read-WpaRunInputSnapshot -ManifestPath $manifestPath -PolicyPath $policyPath

                $snapshot.manifestText | Should -BeExactly $manifestText
                $snapshot.policyText | Should -BeExactly $policyText
                [Convert]::ToHexString($utf8.GetBytes($snapshot.manifestText)) | Should -BeExactly ([Convert]::ToHexString($manifestBytes))
                [Convert]::ToHexString($utf8.GetBytes($snapshot.policyText)) | Should -BeExactly ([Convert]::ToHexString($policyBytes))
            }

            It 'rejects non-canonical input bytes before environment inventory or manager probes' -ForEach @(
                @{ Name='BOM'; Bytes=[byte[]](0xEF,0xBB,0xBF) + [Text.Encoding]::UTF8.GetBytes("schemaVersion: 1`nprofiles: []`npackages: []`n") }
                @{ Name='invalid UTF-8'; Bytes=[byte[]](0xC3,0x28) }
            ) {
                [IO.File]::WriteAllBytes($manifestPath, $Bytes)
                Mock Test-WpaEnvironmentForPolicy { throw 'ENVIRONMENT_PROBE_GUARD' }
                Mock Get-WpaInventoryForPolicy { throw 'INVENTORY_PROBE_GUARD' }
                Mock Test-WpaWingetAvailable { throw 'WINGET_PROBE_GUARD' }
                Mock Test-WpaScoopAvailable { throw 'SCOOP_PROBE_GUARD' }

                { Get-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' } |
                    Should -Throw 'INPUT_UTF8_INVALID'

                Should -Invoke Test-WpaEnvironmentForPolicy -Times 0 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
                Should -Invoke Test-WpaWingetAvailable -Times 0 -Exactly
                Should -Invoke Test-WpaScoopAvailable -Times 0 -Exactly
            }

            It 'stops before inventory and planning when the policy environment is not ready' {
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$false} }
                Mock Get-WpaInventoryForPolicy { throw 'INVENTORY_CALL_GUARD' }
                Mock ConvertTo-WpaPlanObject { throw 'PLAN_CALL_GUARD' }

                Push-Location $TestDrive
                try {
                    { Get-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' } |
                        Should -Throw 'PREVIEW_ENVIRONMENT_NOT_READY'
                } finally {
                    Pop-Location
                }

                Should -Invoke Test-WpaEnvironmentForPolicy -Times 1 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
                Should -Invoke ConvertTo-WpaPlanObject -Times 0 -Exactly
                Test-Path (Join-Path $TestDrive '.wpa') | Should -BeFalse
            }

            It 'rejects partial inventory before planning and leaves no workspace' {
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
                Mock Get-WpaInventoryForPolicy { [pscustomobject]@{status='partial'} }
                Mock ConvertTo-WpaPlanObject { throw 'PLAN_CALL_GUARD' }

                Push-Location $TestDrive
                try {
                    { Get-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' } |
                        Should -Throw 'PREVIEW_INVENTORY_NOT_TRUSTED: partial'
                } finally {
                    Pop-Location
                }

                Should -Invoke Get-WpaInventoryForPolicy -Times 1 -Exactly
                Should -Invoke ConvertTo-WpaPlanObject -Times 0 -Exactly
                Test-Path (Join-Path $TestDrive '.wpa') | Should -BeFalse
            }

            It 'rejects failed inventory before planning and leaves no workspace' {
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
                Mock Get-WpaInventoryForPolicy { [pscustomobject]@{status='failed'} }
                Mock ConvertTo-WpaPlanObject { throw 'PLAN_CALL_GUARD' }

                Push-Location $TestDrive
                try {
                    { Get-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' } |
                        Should -Throw 'PREVIEW_INVENTORY_NOT_TRUSTED: failed'
                } finally {
                    Pop-Location
                }

                Should -Invoke Get-WpaInventoryForPolicy -Times 1 -Exactly
                Should -Invoke ConvertTo-WpaPlanObject -Times 0 -Exactly
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
                Mock ConvertTo-WpaPlanObject {
                    param($Manifest, $Policy, $Inventory, $Now)
                    $script:planManifest = $Manifest
                    $script:planPolicy = $Policy
                    $script:planInventory = $Inventory
                    $script:planNow = $Now
                    $plan
                }

                $result = Get-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd' -Now $now

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
                Should -Invoke ConvertTo-WpaPlanObject -Times 1 -Exactly
            }

            It 'rejects a non-lowercase RunId before reading inputs or probing managers' {
                Mock Test-WpaEnvironmentForPolicy { throw 'ENVIRONMENT_CALL_GUARD' }
                Mock Get-WpaInventoryForPolicy { throw 'INVENTORY_CALL_GUARD' }
                Mock ConvertTo-WpaPlanObject { throw 'PLAN_CALL_GUARD' }
                $missingManifest = Join-Path $TestDrive 'missing-manifest.yaml'
                $missingPolicy = Join-Path $TestDrive 'missing-policy.yaml'

                { Get-WpaRunPreparation -ManifestPath $missingManifest -PolicyPath $missingPolicy -RunId '20260809-010203-AABBCCDD' } |
                    Should -Throw 'RUN_ID_INVALID'

                Should -Invoke Test-WpaEnvironmentForPolicy -Times 0 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
                Should -Invoke ConvertTo-WpaPlanObject -Times 0 -Exactly
            }

            It 'does not call file writers or directory helpers and leaves the TestDrive tree unchanged' {
                $inventory = [pscustomobject]@{status='success'}
                $plan = [pscustomobject]@{manifestHash=('a' * 64);policyHash=('b' * 64)}
                Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
                Mock Get-WpaInventoryForPolicy { $inventory }
                Mock ConvertTo-WpaPlanObject { $plan }
                Mock Write-WpaAtomicJson { throw 'FILE_WRITE_GUARD: JSON writer invoked' }
                Mock Write-WpaAtomicText { throw 'FILE_WRITE_GUARD: text writer invoked' }
                Mock New-Item { throw 'DIRECTORY_CREATE_GUARD: New-Item invoked' }
                $before = @(Get-ChildItem -LiteralPath $TestDrive -File -Recurse | Sort-Object FullName | ForEach-Object {
                    '{0}|{1}' -f [IO.Path]::GetRelativePath($TestDrive, $_.FullName), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                })

                Push-Location $TestDrive
                try {
                    $null = Get-WpaRunPreparation -ManifestPath $manifestPath -PolicyPath $policyPath -RunId '20260809-010203-aabbccdd'
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
                Mock Get-WpaRunPreparation {
                    param($ManifestPath, $PolicyPath, $RunId, $Now)
                    $script:preparation.run.runId = $RunId
                    $script:preparation
                }
                $workspace = Join-Path $TestDrive 'workspace-published'

                $run = New-WpaRun -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $workspace -Now ([datetimeoffset]'2026-08-08T01:02:03Z')

                [object]::ReferenceEquals($run, $script:preparation.run) | Should -BeTrue
                $final = Join-Path $workspace "runs/$($run.runId)"
                [Convert]::ToHexString([IO.File]::ReadAllBytes((Join-Path $final 'manifest.yaml'))) | Should -BeExactly ([Convert]::ToHexString([Text.UTF8Encoding]::new($false).GetBytes($script:preparation.manifestText)))
                [Convert]::ToHexString([IO.File]::ReadAllBytes((Join-Path $final 'policy.yaml'))) | Should -BeExactly ([Convert]::ToHexString([Text.UTF8Encoding]::new($false).GetBytes($script:preparation.policyText)))
                [Convert]::ToHexString([IO.File]::ReadAllBytes((Join-Path $final 'profiles/base.yaml'))) | Should -BeExactly ([Convert]::ToHexString([Text.UTF8Encoding]::new($false).GetBytes($script:preparation.profiles[0].text)))
                foreach ($artifact in @('run.json','inventory.json','plan.json','plan.md')) {
                    Test-Path (Join-Path $final $artifact) | Should -BeTrue
                }
                foreach ($artifact in @('approval.json','apply-result.json','verify-result.json','journal.json','summary.md')) {
                    Test-Path (Join-Path $final $artifact) | Should -BeFalse
                }
                Test-Path (Join-Path $final '.wpa-staging-owner') | Should -BeFalse
                Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeFalse
                Test-Path (Join-Path $final '.wpa-publication-complete') | Should -BeTrue
                Test-Path (Join-Path $final '.wpa-publication-guard-complete') | Should -BeTrue
                Test-Path (Join-Path (Split-Path $final -Parent) ".wpa-publication-guard-$($run.runId)") | Should -BeFalse
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

            It 'keeps both publication handles unavailable for replacement while open' {
                $workspace = Join-Path $TestDrive 'publication-guard-sharing'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runs -StagingPath $staging -ExpectedLeaf ".staging-$($script:preparedRun.runId)"
                try {
                    New-WpaOwnedPublicationGuard -Ownership $ownership -RunId $script:preparedRun.runId | Out-Null
                    $ownership.Stream.Dispose()
                    $ownership.Stream = $null
                    $ownership.DirectoryHandle.Rename((Join-Path $runs $script:preparedRun.runId))
                    New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath (Join-Path $runs $script:preparedRun.runId) | Out-Null

                    foreach ($marker in @(
                        [pscustomobject]@{Handle=$ownership.PublicationGuard;Path=$ownership.PublicationGuardPath;Hash=$ownership.PublicationGuardHash},
                        [pscustomobject]@{Handle=$ownership.PublicationPendingMarker;Path=$ownership.PublicationPendingPath;Hash=$ownership.PublicationPendingHash}
                    )) {
                        { [IO.File]::Open($marker.Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete) } | Should -Throw
                        { [IO.File]::Delete($marker.Path) } | Should -Throw
                        Test-Path -LiteralPath $marker.Path | Should -BeTrue
                        $marker.Handle.GetSha256() | Should -BeExactly $marker.Hash
                    }
                } finally {
                    Close-WpaRunStagingOwnershipHandle -Ownership $ownership
                }
            }

            It 'keeps directory and ancestor renames blocked while the owned handle is open' {
                $workspace = Join-Path $TestDrive 'directory-share-mode/workspace'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
                $final = Join-Path $runs '20260809-010203-aabbccdd'
                $evidence = Join-Path $runs '.staging-evidence-20260809-010203-aabbccdd-deadbeef'
                $markerEvidence = Join-Path $TestDrive '.publication-marker-evidence'
                $afterClose = Join-Path $runs '.staging-after-close'
                [IO.Directory]::CreateDirectory($runs) | Out-Null
                $handle = New-WpaOwnedDirectoryHandleAtomically -Path $staging
                $marker = $null
                try {
                    $handle.Rename($final)
                    [IO.File]::WriteAllText((Join-Path $final 'child.txt'), 'owned')
                    $marker = [WinPkgAgent.Native.OwnedPublicationMarker]::CreateAtomically(
                        (Join-Path $final '.wpa-publication-pending'), 'token')
                    $marker.Rename((Join-Path $final '.wpa-publication-complete'))
                    Test-Path (Join-Path $final '.wpa-publication-complete') | Should -BeTrue
                    $marker.GetSha256() | Should -BeExactly ([Convert]::ToHexString(
                        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('token'))
                    ).ToLowerInvariant())
                    $marker.Rename($markerEvidence)
                    Test-Path (Join-Path $final '.wpa-publication-complete') | Should -BeFalse
                    Test-Path $markerEvidence | Should -BeTrue

                    { [IO.Directory]::Move($final, (Join-Path $runs 'displaced-leaf')) } | Should -Throw
                    { [IO.Directory]::Move($runs, (Join-Path $workspace 'displaced-runs')) } | Should -Throw
                    { [IO.Directory]::Move($workspace, (Join-Path $TestDrive 'displaced-workspace')) } | Should -Throw

                    $handle.Rename($evidence)
                    $marker.Rename((Join-Path $evidence '.wpa-publication-complete'))
                    Test-Path (Join-Path $evidence 'child.txt') | Should -BeTrue
                    Test-Path (Join-Path $evidence '.wpa-publication-complete') | Should -BeTrue
                } finally {
                    if ($null -ne $marker) { $marker.Dispose() }
                    if ($null -ne $handle) { $handle.Dispose() }
                }
                [IO.Directory]::Move($evidence, $afterClose)
                Test-Path $afterClose | Should -BeTrue
            }

            It 'blocks canonical displacement before pending marker creation' {
                $workspace = Join-Path $TestDrive 'pending-attack-workspace'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $final = Join-Path $runs $script:preparedRun.runId
                $outside = Join-Path $TestDrive 'pending-attack-outside'
                $displaced = Join-Path $runs '.displaced-owned-run'
                [IO.Directory]::CreateDirectory($outside) | Out-Null
                $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runs -StagingPath $staging -ExpectedLeaf ".staging-$($script:preparedRun.runId)"
                try {
                    New-WpaOwnedPublicationGuard -Ownership $ownership -RunId $script:preparedRun.runId | Out-Null
                    $ownership.Stream.Dispose()
                    $ownership.Stream = $null
                    $ownership.DirectoryHandle.Rename($final)
                    $attackSucceeded = $false
                    try {
                        [IO.Directory]::Move($final, $displaced)
                        New-Item -ItemType Junction -Path $final -Target $outside -ErrorAction Stop | Out-Null
                        $attackSucceeded = $true
                    } catch {
                        $attackSucceeded = $false
                    }
                    New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $final | Out-Null

                    $attackSucceeded | Should -BeFalse
                    Test-Path (Join-Path $outside '.wpa-publication-pending') | Should -BeFalse
                    Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeTrue
                    Test-Path $ownership.PublicationGuardPath | Should -BeTrue
                } finally {
                    Close-WpaRunStagingOwnershipHandle -Ownership $ownership
                }
            }

            It 'rejects canonical displacement immediately before guard release' {
                $workspace = Join-Path $TestDrive 'guard-release-workspace'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $final = Join-Path $runs $script:preparedRun.runId
                $outside = Join-Path $TestDrive 'guard-release-outside'
                $displaced = Join-Path $runs '.displaced-owned-run'
                [IO.Directory]::CreateDirectory($outside) | Out-Null
                $ownership = New-WpaRunStagingOwnership -WorkspacePath $workspace -RunsPath $runs -StagingPath $staging -ExpectedLeaf ".staging-$($script:preparedRun.runId)"
                try {
                    New-WpaOwnedPublicationGuard -Ownership $ownership -RunId $script:preparedRun.runId | Out-Null
                    $ownership.Stream.Dispose()
                    $ownership.Stream = $null
                    $ownership.DirectoryHandle.Rename($final)
                    New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $final | Out-Null
                    $ownership.PublicationPendingMarker.Dispose()
                    $pending = [pscustomobject]@{
                        IsOpen = $true
                        AttackSucceeded = $false
                        SourcePath = $ownership.PublicationPendingPath
                        DirectoryHandle = $ownership.DirectoryHandle
                        DisplacedPath = $displaced
                        FinalPath = $final
                        OutsidePath = $outside
                    }
                    $pending | Add-Member ScriptMethod Rename {
                        param($DestinationPath)
                        [IO.File]::Move($this.SourcePath, $DestinationPath)
                        $this.DirectoryHandle.Rename($this.DisplacedPath)
                        New-Item -ItemType Junction -Path $this.FinalPath -Target $this.OutsidePath -ErrorAction Stop | Out-Null
                        $outsideComplete = Join-Path $this.OutsidePath ([IO.Path]::GetFileName($DestinationPath))
                        [IO.File]::Move((Join-Path $this.DisplacedPath ([IO.Path]::GetFileName($DestinationPath))), $outsideComplete)
                        $this.SourcePath = $outsideComplete
                        $this.AttackSucceeded = $true
                    }
                    $pending | Add-Member ScriptMethod Dispose { $this.IsOpen = $false }
                    $ownership.PublicationPendingMarker = $pending
                    $ownership.PublicationGuard.Dispose()
                    $guard = [pscustomobject]@{
                        IsOpen = $true
                        RenameCount = 0
                        SourcePath = $ownership.PublicationGuardPath
                    }
                    $guard | Add-Member ScriptMethod Rename {
                        param($DestinationPath)
                        $this.RenameCount++
                        [IO.File]::Move($this.SourcePath, $DestinationPath)
                        $this.SourcePath = $DestinationPath
                    }
                    $guard | Add-Member ScriptMethod Dispose { $this.IsOpen = $false }
                    $ownership.PublicationGuard = $guard

                    $message = try {
                        Complete-WpaOwnedRunPublication -Ownership $ownership -FinalPath $final
                        ''
                    } catch { $_.Exception.Message }

                    $message | Should -BeExactly 'PREVIEW_STAGING_PRESERVED'
                    $pending.AttackSucceeded | Should -BeTrue
                    $guard.RenameCount | Should -Be 0
                    Test-Path (Join-Path $outside '.wpa-publication-complete') | Should -BeTrue
                    Test-Path (Join-Path $outside '.wpa-publication-guard-complete') | Should -BeFalse
                    Test-Path $ownership.PublicationGuardPath | Should -BeTrue
                } finally {
                    Close-WpaRunStagingOwnershipHandle -Ownership $ownership
                }
            }

            It 'rejects a handle-derived final-path mismatch before pending creation' {
                $workspace = Join-Path $TestDrive 'pending-mismatch-workspace'
                $runs = Join-Path $workspace 'runs'
                $final = Join-Path $runs $script:preparedRun.runId
                [IO.Directory]::CreateDirectory($final) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                [IO.File]::WriteAllText($guardPath, 'guard')
                $ownership = [pscustomobject]@{
                    WorkspacePath = $workspace
                    RunsPath = $runs
                    Token = 'token'
                    DirectoryHandle = $null
                    PublicationGuard = [pscustomobject]@{ IsOpen = $true }
                    PublicationGuardPath = $guardPath
                    PublicationPendingMarker = $null
                    PublicationPendingPath = $null
                    PublicationPendingHash = $null
                    ExpectedFileHashes = @{}
                    OwnedFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                }
                $directory = [pscustomobject]@{ IsOpen = $true; FinalPath = (Join-Path $runs 'different-run') }
                $directory | Add-Member ScriptMethod GetFinalPath { $this.FinalPath }
                $ownership.DirectoryHandle = $directory

                $message = try {
                    New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $final
                    ''
                } catch { $_.Exception.Message }

                $message | Should -BeExactly 'PREVIEW_STAGING_PRESERVED'
                $message | Should -Not -Match ([regex]::Escape($TestDrive))
                Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeFalse
            }

            It 'rejects a canonical reparse point before pending creation' {
                $workspace = Join-Path $TestDrive 'pending-reparse-workspace'
                $runs = Join-Path $workspace 'runs'
                $final = Join-Path $runs $script:preparedRun.runId
                $outside = Join-Path $TestDrive 'pending-reparse-outside'
                [IO.Directory]::CreateDirectory($runs) | Out-Null
                [IO.Directory]::CreateDirectory($outside) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                [IO.File]::WriteAllText($guardPath, 'guard')
                New-Item -ItemType Junction -Path $final -Target $outside -ErrorAction Stop | Out-Null
                $directory = [pscustomobject]@{ IsOpen = $true; FinalPath = [IO.Path]::GetFullPath($final) }
                $directory | Add-Member ScriptMethod GetFinalPath { $this.FinalPath }
                $ownership = [pscustomobject]@{
                    WorkspacePath = $workspace
                    RunsPath = $runs
                    Token = 'token'
                    DirectoryHandle = $directory
                    PublicationGuard = [pscustomobject]@{ IsOpen = $true }
                    PublicationGuardPath = $guardPath
                    PublicationPendingMarker = $null
                    PublicationPendingPath = $null
                    PublicationPendingHash = $null
                    ExpectedFileHashes = @{}
                    OwnedFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                }

                { New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $final } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'
                Test-Path (Join-Path $outside '.wpa-publication-pending') | Should -BeFalse
                Test-Path $ownership.PublicationGuardPath | Should -BeTrue
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
                Mock Get-WpaRunPreparation { throw 'simulated preparation failure' }
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
                Test-Path (Join-Path $workspace "runs/.staging-$($script:preparedRun.runId)/.wpa-publication-guard-$($script:preparedRun.runId)") | Should -BeTrue
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

            It 'never publishes a completed staged child replaced with different valid content before rename' {
                $workspace = Join-Path $TestDrive 'workspace-child-content-replacement'
                $staging = Join-Path $workspace "runs/.staging-$($script:preparedRun.runId)"
                $manifestPath = Join-Path $staging 'manifest.yaml'
                $replacement = "# replaced after write`nschemaVersion: 1`nprofiles:`n  - base`npackages: []`n"
                Mock Assert-WpaPlanIntegrity {
                    [IO.File]::Delete($manifestPath)
                    [IO.File]::WriteAllText($manifestPath, $replacement, [Text.UTF8Encoding]::new($false))
                    $true
                }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                Test-Path (Join-Path $workspace "runs/$($script:preparedRun.runId)") | Should -BeFalse
                [IO.File]::ReadAllText($manifestPath) | Should -BeExactly $replacement
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'rolls post-rename content replacement back to handle-bound staging evidence' {
                $workspace = Join-Path $TestDrive 'workspace-post-rename-replacement'
                $runs = Join-Path $workspace 'runs'
                $final = Join-Path $runs $script:preparedRun.runId
                $replacement = "# replaced after rename`nschemaVersion: 1`nprofiles:`n  - base`npackages: []`n"
                Mock Move-WpaOwnedRunStagingDirectory {
                    param($Ownership, $FinalPath)
                    $Ownership.DirectoryHandle.Rename([IO.Path]::GetFullPath($FinalPath))
                    $manifestPath = Join-Path $FinalPath 'manifest.yaml'
                    [IO.File]::Delete($manifestPath)
                    [IO.File]::WriteAllText($manifestPath, $replacement, [Text.UTF8Encoding]::new($false))
                }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                Test-Path $final | Should -BeFalse
                $evidence = @(Get-ChildItem -LiteralPath $runs -Directory -Filter ".staging-evidence-$($script:preparedRun.runId)-*")
                $evidence.Count | Should -Be 1
                [IO.File]::ReadAllText((Join-Path $evidence[0].FullName 'manifest.yaml')) | Should -BeExactly $replacement
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'keeps the immutable guard present while pending moves to evidence' {
                $runs = Join-Path $TestDrive 'evidence-reader-interleaving/runs'
                $final = Join-Path $runs $script:preparedRun.runId
                [IO.Directory]::CreateDirectory($final) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                $pendingPath = Join-Path $final '.wpa-publication-pending'
                [IO.File]::WriteAllText($guardPath, 'guard-token')
                [IO.File]::WriteAllText($pendingPath, 'pending-token')

                $guard = [pscustomobject]@{IsOpen=$true;RenameCount=0}
                $guard | Add-Member -MemberType ScriptMethod -Name Rename -Value { $this.RenameCount++; throw 'guard must not move' }
                $pending = [pscustomobject]@{IsOpen=$true;RenameCount=0;SourcePath=$pendingPath}
                $pending | Add-Member -MemberType ScriptMethod -Name Rename -Value {
                    param($DestinationPath)
                    $this.RenameCount++
                    [IO.File]::Move($this.SourcePath, $DestinationPath)
                    $this.SourcePath = $DestinationPath
                }
                $directory = [pscustomobject]@{IsOpen=$true;GuardPresent=$false}
                $directory | Add-Member -MemberType ScriptMethod -Name Rename -Value {
                    param($DestinationPath)
                    $this.GuardPresent = Test-Path -LiteralPath $guardPath
                    { Read-WpaRun $final } | Should -Throw 'RUN_PUBLICATION_PENDING'
                    { Approve-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                    { Invoke-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                    [IO.Directory]::Move($final, $DestinationPath)
                }
                Mock Read-WpaJsonFile { throw 'metadata must not run' }
                Mock Approve-WpaPlan { throw 'approval must not run' }
                Mock Invoke-WpaPlan { throw 'invoke must not run' }
                Mock Remove-Item {}
                $ownership = [pscustomobject]@{
                    RunsPath=[IO.Path]::GetFullPath($runs); DirectoryHandle=$directory
                    PublicationGuard=$guard; PublicationGuardPath=$guardPath
                    PublicationPendingMarker=$pending; PublicationPendingPath=$pendingPath
                }

                $evidence = Move-WpaOwnedRunToStagingEvidence -Ownership $ownership -RunId $script:preparedRun.runId

                Test-Path -LiteralPath $guardPath | Should -BeTrue
                $directory.GuardPresent | Should -BeTrue
                $guard.RenameCount | Should -Be 0
                $pending.RenameCount | Should -Be 2
                Should -Invoke Read-WpaJsonFile -Times 0 -Exactly
                Should -Invoke Approve-WpaPlan -Times 0 -Exactly
                Should -Invoke Invoke-WpaPlan -Times 0 -Exactly
                Should -Invoke Remove-Item -Times 0 -Exactly
                Test-Path -LiteralPath (Join-Path $evidence '.wpa-publication-pending') | Should -BeTrue
            }

            It 'preserves the guard and canonical directory after three pending-sibling collisions' {
                $runs = Join-Path $TestDrive 'evidence-pending-collisions/runs'
                $final = Join-Path $runs $script:preparedRun.runId
                [IO.Directory]::CreateDirectory($final) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                $pendingPath = Join-Path $final '.wpa-publication-pending'
                [IO.File]::WriteAllText($guardPath, 'guard-token')
                [IO.File]::WriteAllText($pendingPath, 'pending-token')
                $pending = [pscustomobject]@{IsOpen=$true;Attempts=0}
                $pending | Add-Member -MemberType ScriptMethod -Name Rename -Value { $this.Attempts++; throw 'pending collision' }
                $ownership = [pscustomobject]@{
                    RunsPath=[IO.Path]::GetFullPath($runs); DirectoryHandle=[pscustomobject]@{IsOpen=$true}
                    PublicationGuard=[pscustomobject]@{IsOpen=$true}; PublicationGuardPath=$guardPath
                    PublicationPendingMarker=$pending; PublicationPendingPath=$pendingPath
                }
                Mock Remove-Item {}

                { Move-WpaOwnedRunToStagingEvidence -Ownership $ownership -RunId $script:preparedRun.runId } |
                    Should -Throw 'Owned staging evidence could not be preserved.'

                $pending.Attempts | Should -Be 3
                Test-Path -LiteralPath $guardPath | Should -BeTrue
                Test-Path -LiteralPath $final | Should -BeTrue
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'preserves the guard after three directory collisions following a pending move' {
                $runs = Join-Path $TestDrive 'evidence-directory-collisions/runs'
                $final = Join-Path $runs $script:preparedRun.runId
                [IO.Directory]::CreateDirectory($final) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                $pendingPath = Join-Path $final '.wpa-publication-pending'
                [IO.File]::WriteAllText($guardPath, 'guard-token')
                [IO.File]::WriteAllText($pendingPath, 'pending-token')
                $pending = [pscustomobject]@{IsOpen=$true;Attempts=0;SourcePath=$pendingPath}
                $pending | Add-Member -MemberType ScriptMethod -Name Rename -Value {
                    param($DestinationPath)
                    $this.Attempts++
                    [IO.File]::Move($this.SourcePath, $DestinationPath)
                    $this.SourcePath = $DestinationPath
                }
                $directory = [pscustomobject]@{IsOpen=$true;Attempts=0}
                $directory | Add-Member -MemberType ScriptMethod -Name Rename -Value { $this.Attempts++; throw 'directory collision' }
                $ownership = [pscustomobject]@{
                    RunsPath=[IO.Path]::GetFullPath($runs); DirectoryHandle=$directory
                    PublicationGuard=[pscustomobject]@{IsOpen=$true}; PublicationGuardPath=$guardPath
                    PublicationPendingMarker=$pending; PublicationPendingPath=$pendingPath
                }
                Mock Remove-Item {}

                { Move-WpaOwnedRunToStagingEvidence -Ownership $ownership -RunId $script:preparedRun.runId } |
                    Should -Throw 'Owned staging evidence could not be preserved.'

                $pending.Attempts | Should -Be 1
                $directory.Attempts | Should -Be 3
                Test-Path -LiteralPath $guardPath | Should -BeTrue
                Test-Path -LiteralPath $final | Should -BeTrue
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'preserves the guard when pending cannot move into moved evidence' {
                $runs = Join-Path $TestDrive 'evidence-pending-final-failure/runs'
                $final = Join-Path $runs $script:preparedRun.runId
                [IO.Directory]::CreateDirectory($final) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                $pendingPath = Join-Path $final '.wpa-publication-pending'
                [IO.File]::WriteAllText($guardPath, 'guard-token')
                [IO.File]::WriteAllText($pendingPath, 'pending-token')
                $pending = [pscustomobject]@{IsOpen=$true;Attempts=0;SourcePath=$pendingPath}
                $pending | Add-Member -MemberType ScriptMethod -Name Rename -Value {
                    param($DestinationPath)
                    $this.Attempts++
                    if ($this.Attempts -eq 1) { [IO.File]::Move($this.SourcePath, $DestinationPath); $this.SourcePath = $DestinationPath; return }
                    throw 'pending evidence move failure'
                }
                $directory = [pscustomobject]@{IsOpen=$true;Attempts=0}
                $directory | Add-Member -MemberType ScriptMethod -Name Rename -Value {
                    param($DestinationPath)
                    $this.Attempts++
                    if ($this.Attempts -eq 1) { [IO.Directory]::Move($final, $DestinationPath); return }
                    throw 'directory retry collision'
                }
                $ownership = [pscustomobject]@{
                    RunsPath=[IO.Path]::GetFullPath($runs); DirectoryHandle=$directory
                    PublicationGuard=[pscustomobject]@{IsOpen=$true}; PublicationGuardPath=$guardPath
                    PublicationPendingMarker=$pending; PublicationPendingPath=$pendingPath
                }
                Mock Remove-Item {}

                { Move-WpaOwnedRunToStagingEvidence -Ownership $ownership -RunId $script:preparedRun.runId } |
                    Should -Throw 'Owned staging evidence could not be preserved.'

                $pending.Attempts | Should -Be 2
                Test-Path -LiteralPath $guardPath | Should -BeTrue
                @(Get-ChildItem -LiteralPath $runs -Directory -Filter '.staging-evidence-*').Count | Should -Be 1
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'exhausts three collision-safe evidence renames without deleting evidence' {
                $runs = Join-Path $TestDrive 'evidence-collision-exhaustion/runs'
                [IO.Directory]::CreateDirectory($runs) | Out-Null
                $handle = [pscustomobject]@{IsOpen=$true;Attempts=0}
                $handle | Add-Member -MemberType ScriptMethod -Name Rename -Value {
                    param($DestinationPath)
                    $this.Attempts++
                    throw [IO.IOException]::new('destination collision')
                }
                $guard = [pscustomobject]@{IsOpen=$true}
                $ownership = [pscustomobject]@{
                    DirectoryHandle=$handle
                    PublicationGuard=$guard
                    PublicationPendingMarker=$handle
                    PublicationPendingPath=(Join-Path $runs '.wpa-publication-pending')
                    RunsPath=[IO.Path]::GetFullPath($runs)
                }
                Mock Remove-Item {}

                { Move-WpaOwnedRunToStagingEvidence -Ownership $ownership -RunId $script:preparedRun.runId } |
                    Should -Throw 'Owned staging evidence could not be preserved.'

                $handle.Attempts | Should -Be 3
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'leaves an exhausted post-rename run pending and rejects read approval and invoke consumers' {
                $workspace = Join-Path $TestDrive 'workspace-evidence-exhaustion'
                $runs = Join-Path $workspace 'runs'
                $final = Join-Path $runs $script:preparedRun.runId
                $replacement = "# replaced after rename`nschemaVersion: 1`nprofiles:`n  - base`npackages: []`n"
                Mock Move-WpaOwnedRunStagingDirectory {
                    param($Ownership, $FinalPath)
                    $Ownership.DirectoryHandle.Rename([IO.Path]::GetFullPath($FinalPath))
                    $manifestPath = Join-Path $FinalPath 'manifest.yaml'
                    [IO.File]::Delete($manifestPath)
                    [IO.File]::WriteAllText($manifestPath, $replacement, [Text.UTF8Encoding]::new($false))
                }
                Mock Move-WpaOwnedRunToStagingEvidence { throw 'Owned staging evidence could not be preserved.' }
                Mock Approve-WpaPlan { throw 'approval must not run' }
                Mock Invoke-WpaPlan { throw 'invoke must not run' }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                Test-Path $final | Should -BeTrue
                Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeTrue
                [IO.File]::ReadAllText((Join-Path $final 'manifest.yaml')) | Should -BeExactly $replacement
                { Read-WpaRun $final } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Approve-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Invoke-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                Should -Invoke Approve-WpaPlan -Times 0 -Exactly
                Should -Invoke Invoke-WpaPlan -Times 0 -Exactly
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'leaves a completion-marker rename failure pending and rejects read approval and invoke consumers' {
                $workspace = Join-Path $TestDrive 'workspace-completion-marker-failure'
                $final = Join-Path $workspace "runs/$($script:preparedRun.runId)"
                Mock Complete-WpaOwnedRunPublication { throw 'simulated completion marker failure' }
                Mock Approve-WpaPlan { throw 'approval must not run' }
                Mock Invoke-WpaPlan { throw 'invoke must not run' }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                Test-Path $final | Should -BeTrue
                Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeTrue
                Test-Path (Join-Path $final '.wpa-publication-complete') | Should -BeFalse
                { Read-WpaRun $final } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Approve-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Invoke-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                Should -Invoke Approve-WpaPlan -Times 0 -Exactly
                Should -Invoke Invoke-WpaPlan -Times 0 -Exactly
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'does not rename the guard when pending completion fails' {
                $runs = Join-Path $TestDrive 'completion-pending-failure/runs'
                $final = Join-Path $runs $script:preparedRun.runId
                [IO.Directory]::CreateDirectory($final) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                $pendingPath = Join-Path $final '.wpa-publication-pending'
                [IO.File]::WriteAllText($guardPath, 'guard-token')
                [IO.File]::WriteAllText($pendingPath, 'pending-token')
                $guard = [pscustomobject]@{IsOpen=$true;RenameCount=0}
                $guard | Add-Member -MemberType ScriptMethod -Name Rename -Value { $this.RenameCount++; throw 'guard rename must not run' }
                $pending = [pscustomobject]@{IsOpen=$true}
                $pending | Add-Member -MemberType ScriptMethod -Name Rename -Value { throw 'pending completion failure' }
                $ownership = [pscustomobject]@{
                    RunsPath=[IO.Path]::GetFullPath($runs); PublicationGuard=$guard; PublicationGuardPath=$guardPath
                    PublicationPendingMarker=$pending; PublicationPendingPath=$pendingPath
                }
                Mock Read-WpaJsonFile { throw 'metadata must not run' }
                Mock Approve-WpaPlan { throw 'approval must not run' }
                Mock Invoke-WpaPlan { throw 'invoke must not run' }
                Mock Assert-WpaOwnedPublishedDirectoryTrust { $true }

                { Complete-WpaOwnedRunPublication -Ownership $ownership -FinalPath $final } |
                    Should -Throw '*pending completion failure*'

                $guard.RenameCount | Should -Be 0
                Test-Path -LiteralPath $guardPath | Should -BeTrue
                Test-Path -LiteralPath $pendingPath | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $final '.wpa-publication-complete') | Should -BeFalse
                { Read-WpaRun $final } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Approve-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Invoke-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                Should -Invoke Read-WpaJsonFile -Times 0 -Exactly
                Should -Invoke Approve-WpaPlan -Times 0 -Exactly
                Should -Invoke Invoke-WpaPlan -Times 0 -Exactly
            }

            It 'preserves the sibling guard when guard completion fails after pending success' {
                $runs = Join-Path $TestDrive 'completion-guard-failure/runs'
                $final = Join-Path $runs $script:preparedRun.runId
                [IO.Directory]::CreateDirectory($final) | Out-Null
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                $pendingPath = Join-Path $final '.wpa-publication-pending'
                [IO.File]::WriteAllText($guardPath, 'guard-token')
                [IO.File]::WriteAllText($pendingPath, 'pending-token')
                $guard = [pscustomobject]@{IsOpen=$true;RenameCount=0}
                $guard | Add-Member -MemberType ScriptMethod -Name Rename -Value { $this.RenameCount++; throw 'guard completion failure' }
                $pending = [pscustomobject]@{IsOpen=$true;SourcePath=$pendingPath}
                $pending | Add-Member -MemberType ScriptMethod -Name Rename -Value {
                    param($DestinationPath)
                    [IO.File]::Move($this.SourcePath, $DestinationPath)
                    $this.SourcePath = $DestinationPath
                }
                $ownership = [pscustomobject]@{
                    RunsPath=[IO.Path]::GetFullPath($runs); PublicationGuard=$guard; PublicationGuardPath=$guardPath
                    PublicationPendingMarker=$pending; PublicationPendingPath=$pendingPath
                }
                Mock Read-WpaJsonFile { throw 'metadata must not run' }
                Mock Approve-WpaPlan { throw 'approval must not run' }
                Mock Invoke-WpaPlan { throw 'invoke must not run' }
                Mock Assert-WpaOwnedPublishedDirectoryTrust { $true }

                { Complete-WpaOwnedRunPublication -Ownership $ownership -FinalPath $final } |
                    Should -Throw '*guard completion failure*'

                $guard.RenameCount | Should -Be 1
                Test-Path -LiteralPath $guardPath | Should -BeTrue
                Test-Path -LiteralPath $pendingPath | Should -BeFalse
                Test-Path -LiteralPath (Join-Path $final '.wpa-publication-complete') | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $final '.wpa-publication-guard-complete') | Should -BeFalse
                { Read-WpaRun $final } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Approve-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                { Invoke-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
                Should -Invoke Read-WpaJsonFile -Times 0 -Exactly
                Should -Invoke Approve-WpaPlan -Times 0 -Exactly
                Should -Invoke Invoke-WpaPlan -Times 0 -Exactly
            }

            It 'leaves the sibling guard when the pre-canonical guard move fails' {
                $workspace = Join-Path $TestDrive 'workspace-pre-canonical-guard-failure'
                $runs = Join-Path $workspace 'runs'
                $guardPath = Join-Path $runs ".wpa-publication-guard-$($script:preparedRun.runId)"
                $script:preRenameGuard = [pscustomobject]@{IsOpen=$true;RenameCount=0}
                $script:preRenameGuard | Add-Member -MemberType ScriptMethod -Name Rename -Value { $this.RenameCount++; throw 'guard staging move failure' }
                $script:preRenameGuard | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.IsOpen=$false }
                Mock New-WpaOwnedPublicationGuard {
                    param($Ownership, $RunId)
                    $guardPathForTest = Join-Path $Ownership.RunsPath ".wpa-publication-guard-$RunId"
                    [IO.File]::WriteAllText($guardPathForTest, 'guard-token')
                    $Ownership.PublicationGuardPath = $guardPathForTest
                    $Ownership.PublicationGuard = $script:preRenameGuard
                }
                Mock Assert-WpaPlanIntegrity { throw 'pre-canonical failure' }
                Mock Remove-Item {}

                { Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace } |
                    Should -Throw 'PREVIEW_STAGING_PRESERVED'

                $script:preRenameGuard.RenameCount | Should -Be 1
                Test-Path -LiteralPath $guardPath | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $runs ".staging-$($script:preparedRun.runId)") | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $runs $script:preparedRun.runId) | Should -BeFalse
                Should -Invoke Remove-Item -Times 0 -Exactly
            }

            It 'blocks deterministic staging-path replacement before publication' {
                $workspace = Join-Path $TestDrive 'workspace-directory-substitution'
                $runs = Join-Path $workspace 'runs'
                $staging = Join-Path $runs ".staging-$($script:preparedRun.runId)"
                $displacedOwned = Join-Path $runs '.displaced-owned'
                $foreignFile = Join-Path $staging 'foreign.txt'
                $script:directorySubstituted = $false
                Mock Assert-WpaStagingOwnershipMarkerReleased {
                    if (-not $script:directorySubstituted) {
                        $script:directorySubstituted = $true
                        try {
                            [IO.Directory]::Move($staging, $displacedOwned)
                            [IO.Directory]::CreateDirectory($staging) | Out-Null
                            [IO.File]::WriteAllText($foreignFile, 'preserve-replacement')
                        } catch {
                            $script:directorySubstituted = $false
                        }
                    }
                    $true
                }
                $published = Publish-WpaPreparedRun -Preparation $script:preparation -WorkspacePath $workspace

                $published | Should -Be (Join-Path $runs $script:preparedRun.runId)
                $script:directorySubstituted | Should -BeFalse
                [IO.File]::ReadAllText((Join-Path $published 'manifest.yaml')) | Should -BeExactly $script:preparation.manifestText
                Test-Path (Join-Path $published 'foreign.txt') | Should -BeFalse
                Test-Path $foreignFile | Should -BeFalse
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
                    { Protect-WpaOwnedRunStagingDirectory -Ownership $ownership } |
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
                    { Protect-WpaOwnedRunStagingDirectory -Ownership $ownership } |
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
                    { Protect-WpaOwnedRunStagingDirectory -Ownership $ownership } |
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
                    Protect-WpaOwnedRunStagingDirectory -Ownership $ownership
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
                Mock Get-WpaRunPreparation { throw 'PREPARATION_CALLED' }
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
                Should -Invoke Get-WpaRunPreparation -Times 0 -Exactly
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
