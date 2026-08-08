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
    }
}
