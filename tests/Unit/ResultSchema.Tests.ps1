$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot '../../scripts/Private/ExitCode.ps1')

Describe 'WinPkgAgent apply and verify result schemas' {
    InModuleScope WinPkgAgent {
        BeforeAll {
            $script:planId = [guid]::NewGuid().ToString()
            $script:apply = [pscustomobject][ordered]@{
                schemaVersion=1;planId=$script:planId;status='success';startedAt='2026-08-05T00:00:00Z';finishedAt='2026-08-05T00:01:00Z'
                operations=@([pscustomobject]@{
                    manager='scoop';id='tool';operation='install';status='completed';reasonCode='COMMAND_SUCCEEDED';exitCode=0;durationMs=5;timedOut=$false;rebootRequired=$false
                    stdoutHash='c6d4f5ecf6b5f9a8a8ad89bcf7df5d5d5b4b4ecfce5f8f2b9e0a3f2c5d2a7f0f1'
                    stderrHash='c6d4f5ecf6b5f9a8a8ad89bcf7df5d5d5b4b4ecfce5f8f2b9e0a3f2c5d2a7f0f1'
                    stdoutLength=0;stderrLength=0;stdoutTruncated=$false;stderrTruncated=$false;diagnosticLoggingEnabled=$false
                })
                rebootRequired=$false;warnings=@()
            }
            $script:verify = [pscustomobject][ordered]@{
                schemaVersion=1;planId=$script:planId;status='success';verifiedAt='2026-08-05T00:01:00Z'
                items=@([pscustomobject]@{name='tool';manager='scoop';id='tool';status='verified';reasonCode='EXPECTED_STATE_PRESENT';actualVersion='1.0.0'})
                rebootRequired=$false
            }
        }

        It 'accepts valid apply and verify samples' {
            Test-WpaDataSchema -Data $script:apply -SchemaName apply-result | Should -BeTrue
            Test-WpaDataSchema -Data $script:verify -SchemaName verify-result | Should -BeTrue
        }

        It 'accepts default no-body operation payload' {
            $sample = [pscustomobject]@{
                schemaVersion = 1
                planId = $script:planId
                status = 'success'
                startedAt = '2026-08-05T00:00:00Z'
                finishedAt = '2026-08-05T00:01:00Z'
                operations = @(
                    [pscustomobject]@{
                        manager = 'scoop'
                        id = 'tool'
                        operation = 'install'
                        status = 'completed'
                        reasonCode = 'COMMAND_SUCCEEDED'
                        exitCode = 0
                        durationMs = 5
                        timedOut = $false
                        rebootRequired = $false
                        stdoutHash = 'c6d4f5ecf6b5f9a8a8ad89bcf7df5d5d5b4b4ecfce5f8f2b9e0a3f2c5d2a7f0f1'
                        stderrHash = 'c6d4f5ecf6b5f9a8a8ad89bcf7df5d5d5b4b4ecfce5f8f2b9e0a3f2c5d2a7f0f1'
                        stdoutLength = 0
                        stderrLength = 0
                        stdoutTruncated = $false
                        stderrTruncated = $false
                        diagnosticLoggingEnabled = $false
                    }
                )
                rebootRequired = $false
                warnings = @()
            }
            Test-WpaDataSchema -Data $sample -SchemaName apply-result | Should -BeTrue
        }

        It 'rejects verify fields inside an apply operation' {
            $sample=$script:apply | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $sample.operations[0] | Add-Member -NotePropertyName actualVersion -NotePropertyValue '1.0.0'
            { Test-WpaDataSchema -Data $sample -SchemaName apply-result } | Should -Throw
        }

        It 'rejects apply fields inside a verify item' {
            $sample=$script:verify | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $sample.items[0] | Add-Member -NotePropertyName operation -NotePropertyValue install
            { Test-WpaDataSchema -Data $sample -SchemaName verify-result } | Should -Throw
        }

        It 'rejects unknown fields in both result types' {
            $applySample=$script:apply | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $applySample | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
            $verifySample=$script:verify | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $verifySample | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
            { Test-WpaDataSchema -Data $applySample -SchemaName apply-result } | Should -Throw
            { Test-WpaDataSchema -Data $verifySample -SchemaName verify-result } | Should -Throw
        }

        It 'rejects legacy operation fields stdout/stderr/hash/length/truncated' {
            $sample=$script:apply | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $sample.operations[0] | Add-Member -NotePropertyName stdout -NotePropertyValue 'legacy-stdout' -Force
            $sample.operations[0] | Add-Member -NotePropertyName stderr -NotePropertyValue 'legacy-stderr' -Force
            $sample.operations[0] | Add-Member -NotePropertyName hash -NotePropertyValue 'legacy-hash' -Force
            $sample.operations[0] | Add-Member -NotePropertyName length -NotePropertyValue 100 -Force
            $sample.operations[0] | Add-Member -NotePropertyName truncated -NotePropertyValue $true -Force
            { Test-WpaDataSchema -Data $sample -SchemaName apply-result } | Should -Throw
        }

        It 'rejects invalid statuses and missing required fields' {
            $applySample=$script:apply | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $applySample.status='unknown'
            { Test-WpaDataSchema -Data $applySample -SchemaName apply-result } | Should -Throw
            $verifySample=$script:verify | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $verifySample.items[0].status='completed'
            { Test-WpaDataSchema -Data $verifySample -SchemaName verify-result } | Should -Throw
            $missing=$script:apply | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $missing.PSObject.Properties.Remove('planId')
            { Test-WpaDataSchema -Data $missing -SchemaName apply-result } | Should -Throw
        }

        It 'rejects non ISO 8601 timestamps' {
            $sample=$script:apply | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $sample.startedAt='not-a-timestamp'
            { Test-WpaDataSchema -Data $sample -SchemaName apply-result } | Should -Throw
            $verifySample=$script:verify | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $verifySample.verifiedAt='2026/08/05 00:01:00'
            { Test-WpaDataSchema -Data $verifySample -SchemaName verify-result } | Should -Throw
        }

        It 'uses only the separate schemas at the runtime validation boundary' {
            $source=Get-Content (Join-Path $PSScriptRoot '../../src/WinPkgAgent/Public/Invoke-WpaPlan.ps1') -Raw
            $source | Should -Match 'SchemaName apply-result'
            $source | Should -Match 'SchemaName verify-result'
            $source | Should -Not -Match 'SchemaName result([\s-]|$)'
        }

        It 'maps apply and verify statuses to the existing CLI exit codes' {
            Get-WpaCliExitCode -Command invoke -Result ([pscustomobject]@{apply=@{status='failed'};verify=@{status='not-run'}}) | Should -Be 3
            Get-WpaCliExitCode -Command invoke -Result ([pscustomobject]@{apply=@{status='success'};verify=@{status='indeterminate'}}) | Should -Be 4
            Get-WpaCliExitCode -Command invoke -Result ([pscustomobject]@{apply=@{status='success'};verify=@{status='reboot-required'}}) | Should -Be 5
        }
    }
}
