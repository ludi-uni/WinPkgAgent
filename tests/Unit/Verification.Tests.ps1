$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent verification' {
    InModuleScope WinPkgAgent {
        It 'marks an installed expected version as verified' {
            $action = [pscustomobject]@{ name='tool';manager='scoop';id='tool';operation='upgrade';targetVersion='2.0.0';verification=$null }
            $inventory = [pscustomobject]@{ packages=@([pscustomobject]@{manager='scoop';id='tool';installedVersion='2.0.0'}) }
            (Test-WpaExpectedState -Action $action -Inventory $inventory).status | Should -Be 'verified'
        }

        It 'marks a version mismatch as failed' {
            $action = [pscustomobject]@{ name='tool';manager='scoop';id='tool';operation='upgrade';targetVersion='2.0.0';verification=$null }
            $inventory = [pscustomobject]@{ packages=@([pscustomobject]@{manager='scoop';id='tool';installedVersion='1.9.0'}) }
            (Test-WpaExpectedState -Action $action -Inventory $inventory).status | Should -Be 'verification-failed'
        }

        It 'returns indeterminate when manager inventory cannot identify the package' {
            $action = [pscustomobject]@{ name='tool';manager='scoop';id='tool';operation='install';targetVersion=$null;verification=$null }
            $inventory = [pscustomobject]@{ packages=@() }
            (Test-WpaExpectedState -Action $action -Inventory $inventory).status | Should -Be 'indeterminate'
        }

        It 'fails when an optional verification command is not on PATH' {
            $action = [pscustomobject]@{ name='tool';manager='scoop';id='tool';operation='install';targetVersion=$null;verification=[pscustomobject]@{command='wpa-command-that-does-not-exist';arguments=@('--version')} }
            $inventory = [pscustomobject]@{ packages=@([pscustomobject]@{manager='scoop';id='tool';installedVersion='1.0.0'}) }
            $result=Test-WpaExpectedState -Action $action -Inventory $inventory
            $result.status | Should -Be 'verification-failed'
            $result.reasonCode | Should -Be 'COMMAND_NOT_ON_PATH'
        }

        It 'fails when the safe version command returns a nonzero exit code' {
            $action = [pscustomobject]@{ name='tool';manager='scoop';id='tool';operation='install';targetVersion=$null;verification=[pscustomobject]@{command='pwsh';arguments=@('--version')} }
            $inventory = [pscustomobject]@{ packages=@([pscustomobject]@{manager='scoop';id='tool';installedVersion='1.0.0'}) }
            Mock Get-Command {[pscustomobject]@{Source='pwsh.exe'}} -ParameterFilter {$Name -eq 'pwsh'}
            Mock Invoke-WpaProcess {[pscustomobject]@{ExitCode=1;TimedOut=$false}}
            $result=Test-WpaExpectedState -Action $action -Inventory $inventory
            $result.status | Should -Be 'verification-failed'
            $result.reasonCode | Should -Be 'COMMAND_VERIFICATION_FAILED'
        }

        Context 'resumed verification policy binding' {
            BeforeEach {
                $script:resumePolicy = [pscustomobject][ordered]@{schemaVersion=1;allowedManagers=@('scoop')}
                $script:resumePlan = [pscustomobject]@{
                    planId='plan-1'
                    policyHash=(Get-WpaObjectHash $script:resumePolicy)
                    actions=@([pscustomobject]@{manager='scoop';id='tool'})
                }
                $script:resumeApply = [pscustomobject]@{
                    planId='plan-1'
                    rebootRequired=$true
                    operations=@([pscustomobject]@{manager='scoop';id='tool';status='completed'})
                }
                Mock Read-WpaJsonFile { param([string]$Path) if($Path -eq 'plan.json'){$script:resumePlan}else{$script:resumeApply} }
                Mock Test-WpaDataSchema { $true }
                Mock Read-WpaPolicyFile { $script:resumePolicy }
                Mock Test-WpaExpectedState { [pscustomobject]@{status='verified';reasonCode='EXPECTED_STATE_PRESENT'} }
                Mock Write-WpaAtomicJson {}
            }

            It 'rejects a mismatched policy before any inventory or manager probe' {
                $script:resumePlan.policyHash = ('f' * 64)
                Mock Get-WpaInventoryForPolicy { throw 'INVENTORY_PROBE_GUARD' }
                Mock Test-WpaWingetAvailable { throw 'WINGET_PROBE_GUARD' }
                Mock Test-WpaScoopAvailable { throw 'SCOOP_PROBE_GUARD' }

                { Resume-WpaVerification -PlanPath plan.json -ApplyResultPath apply.json -PolicyPath policy.yaml -VerifyOutputPath $null -WhatIf } |
                    Should -Throw 'RESUME_POLICY_MISMATCH'

                Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
                Should -Invoke Test-WpaWingetAvailable -Times 0 -Exactly
                Should -Invoke Test-WpaScoopAvailable -Times 0 -Exactly
            }

            It 'uses the matched parsed policy object to scope resumed inventory' {
                $script:inventoryPolicy = $null
                Mock Get-WpaInventoryForPolicy {
                    param($Policy)
                    $script:inventoryPolicy = $Policy
                    [pscustomobject]@{packages=@()}
                }

                $result = Resume-WpaVerification -PlanPath plan.json -ApplyResultPath apply.json -PolicyPath policy.yaml -VerifyOutputPath $null -WhatIf

                [object]::ReferenceEquals($script:resumePolicy, $script:inventoryPolicy) | Should -BeTrue
                $result.status | Should -BeExactly 'success'
                Should -Invoke Read-WpaPolicyFile -Times 1 -Exactly
                Should -Invoke Get-WpaInventoryForPolicy -Times 1 -Exactly
            }
        }
    }
}
