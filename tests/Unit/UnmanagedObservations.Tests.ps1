Describe 'unmanaged winget observations' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }

    It 'excludes export IDs and classifies source-less IDs as manual mappings' {
        InModuleScope WinPkgAgent {
            $list = @'
Name                 Id                         Version  Available  Source
-------------------  -------------------------  -------  ---------  ------
Ablaze Floorp         ARP\Machine\X64\Floorp     12.10.4
7-Zip                7zip.7zip                  25.01    26.02      winget
Example Tool         Example.Tool                1.2.3               winget
'@
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\winget.exe' }
            Mock Invoke-WpaProcess {
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = $list; StdErr = ''; DurationMs = 1 }
            }

            $result = Get-WpaWingetUnmanagedObservation -KnownIds @('7zip.7zip')

            $result.status | Should -Be 'success'
            @($result.observations) | Should -HaveCount 2
            $result.observations[0].actionability | Should -Be 'manual-mapping'
            $result.observations[0].reasonCode | Should -Be 'UNMANAGED_ID_REQUIRES_MAPPING'
            $result.observations[1].actionability | Should -Be 'manager-candidate'
            Should -Invoke Invoke-WpaProcess -ParameterFilter { $Arguments -contains 'list' -and $Arguments -contains '--disable-interactivity' } -Times 1 -Exactly
            Should -Invoke Invoke-WpaProcess -ParameterFilter { $Arguments -contains '--accept-source-agreements' -or $Arguments -contains '--accept-package-agreements' } -Times 0 -Exactly
        }
    }

    It 'returns failed without observations when list output is malformed' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\winget.exe' }
            Mock Invoke-WpaProcess { [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'unknown output'; StdErr = ''; DurationMs = 1 } }

            $result = Get-WpaWingetUnmanagedObservation -KnownIds @()

            $result.status | Should -Be 'failed'
            @($result.observations) | Should -HaveCount 0
            $result.warning | Should -Match 'unavailable or malformed'
        }
    }

    It 'writes a separate pending review artifact without creating an active manifest' {
        InModuleScope WinPkgAgent {
            $inventoryPath = Join-Path $TestDrive 'inventory.json'
            $outputPath = Join-Path $TestDrive 'unmanaged-candidate.json'
            [IO.File]::WriteAllText($inventoryPath, (@{
                schemaVersion = 2
                policyHash = ('a' * 64)
                managerScope = @('winget')
                environment = @{ id = 'environment-id' }
                collectedAt = '2026-08-08T00:00:00Z'
                status = 'success'
                managers = @(@{ manager='winget'; version='1.0'; status='success'; timedOut=$false; warning=$null })
                packages = @(@{ manager='winget'; id='7zip.7zip'; displayName='7-Zip'; installedVersion='25.01'; availableVersion=$null; source='winget'; scope=$null; metadata=@{} })
                warnings = @()
            } | ConvertTo-Json -Depth 20))
            Mock Get-WpaWingetUnmanagedObservation {
                [pscustomobject]@{
                    status = 'success'
                    warning = $null
                    observations = @([pscustomobject]@{
                        displayName='Ablaze Floorp'; observedId='ARP\Machine\X64\Floorp'; installedVersion='12.10.4'; availableVersion=$null; source=$null
                        actionability='manual-mapping'; reasonCode='UNMANAGED_ID_REQUIRES_MAPPING'; reviewStatus='pending'; detectedBy='winget-list'
                    })
                }
            }

            $result = Export-WpaUnmanagedCandidate -InventoryPath $inventoryPath -OutputPath $outputPath
            $artifact = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json

            $result.status | Should -Be 'success'
            $result.count | Should -Be 1
            $artifact.reviewStatus | Should -Be 'pending'
            $artifact.observations[0].actionability | Should -Be 'manual-mapping'
            $artifact.observations[0].reasonCode | Should -Be 'UNMANAGED_ID_REQUIRES_MAPPING'
            (Test-Path -LiteralPath (Join-Path $TestDrive 'manifest.yaml')) | Should -BeFalse
        }
    }
}
