$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'package migration candidate export' {
    It 'emits a pending manifest-safe candidate from detected package metadata' {
        InModuleScope WinPkgAgent {
            $inventory = [pscustomobject]@{
                schemaVersion = 1
                environment = [pscustomobject]@{ id = 'env' }
                collectedAt = '2026-08-08T00:00:00Z'
                status = 'partial'
                managers = @()
                packages = @([pscustomobject]@{
                    manager = 'winget'
                    id = 'Notepad++.Notepad++'
                    displayName = 'Notepad++'
                    installedVersion = '8.9.6.4'
                    availableVersion = $null
                    source = $null
                    scope = $null
                    metadata = [pscustomobject]@{ detectedBy = 'winget-export' }
                })
                warnings = @()
            }
            Mock Read-WpaJsonFile { $inventory }
            Mock Test-WpaDataSchema { $true }
            $output = Join-Path $TestDrive 'migration-candidate.yaml'

            Export-WpaManifestCandidate -InventoryPath 'inventory.json' -OutputPath $output | Out-Null

            $text = Get-Content -LiteralPath $output -Raw
            $text | Should -Match "^profiles: \[\]"
            $text | Should -Match "name: 'notepad-.notepad'"
            $text | Should -Match "version: '8.9.6.4'"
            $text | Should -Match 'reviewStatus: pending'
            $text | Should -Match 'does not prove original manager ownership'
        }
    }
}
