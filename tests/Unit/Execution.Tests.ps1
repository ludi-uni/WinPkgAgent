$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent sequential execution safety' {
    InModuleScope WinPkgAgent {
        BeforeEach {
            $script:policy=[pscustomobject]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch','minor');allowUninstall=$false;allowedManagers=@('winget','scoop');allowedSources=@('main','winget');protectedPackages=@();dangerousCategories=@('driver');requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=600;rebootHandling='record-only';unknownVersionHandling='block'}
            $script:inventory=[pscustomobject]@{schemaVersion=1;environment=@{id='env'};status='success';managers=@(@{manager='scoop';status='success';version='1'});packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            $actions=@('one','two'|ForEach-Object{[pscustomobject]@{name=$_;manager='scoop';id=$_;source='main';classification='install';operation='install';reasonCode='PACKAGE_NOT_INSTALLED';reason='missing';risk='low';targetVersion=$null;verification=$null}})
            $script:plan=[pscustomobject][ordered]@{schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z';environmentId='env';manifestHash=('a'*64);policyHash=(Get-WpaObjectHash $policy);inventoryHash=(Get-WpaInventoryStateHash $inventory);actions=$actions;blockedOperations=@();warnings=@();contentHash=$null;planHash=$null}
            $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
            $script:approval=[pscustomobject]@{schemaVersion=1;planId=$plan.planId;planHash=$plan.planHash;approvedAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z'}
            Mock Test-WpaDataSchema {$true};Mock Get-WpaEnvironmentId {'env'};Mock Read-WpaPolicyFile {$policy};Mock Get-WpaInventory {$inventory}
            Mock Read-WpaJsonFile {param($Path) if($Path -eq 'plan.json'){$plan}elseif($Path -eq 'approval.json'){$approval}else{throw 'missing approval'}}
        }

        It 'rejects a missing approval before any mutation' {
            Mock Invoke-WpaManagerAction {throw 'must not run'}
            {Invoke-WpaPlan -PlanPath plan.json -ApprovalPath missing.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false} | Should -Throw
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
        }

        It 'stops after one failure and records later operations as not run' {
            Mock Invoke-WpaManagerAction {[pscustomobject]@{ExitCode=1;TimedOut=$false;DurationMs=5;StdOut='';StdErr='failed'}}
            $result=Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false
            Should -Invoke Invoke-WpaManagerAction -Times 1 -Exactly
            $result.apply.status | Should -Be 'partial-failure'
            $result.apply.operations[0].status | Should -Be 'failed'
            $result.apply.operations[1].status | Should -Be 'not-run'
        }

        It 'rejects policy drift before any mutation' {
            $changed=$policy.PSObject.Copy();$changed.maxOperations=9
            Mock Read-WpaPolicyFile {$changed};Mock Invoke-WpaManagerAction {throw 'must not run'}
            {Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false} | Should -Throw '*Policy changed*'
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
        }

        It 'rejects inventory drift before any mutation' {
            $changedInventory=$inventory.PSObject.Copy();$changedInventory.packages=@([pscustomobject]@{manager='scoop';id='unexpected';displayName='unexpected';installedVersion='1.0';availableVersion=$null;source='main';scope='user'})
            Mock Get-WpaInventory {$changedInventory};Mock Invoke-WpaManagerAction {throw 'must not run'}
            {Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false} | Should -Throw '*Inventory state changed*'
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
        }

        It 'rejects an expired plan and a different target environment before mutation' {
            Mock Invoke-WpaManagerAction {throw 'must not run'}
            $plan.expiresAt='2020-01-01T00:00:00Z'
            $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
            $approval.planHash=$plan.planHash
            {Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false} | Should -Throw '*Plan has expired*'
            $plan.expiresAt='2099-01-01T00:00:00Z';$plan.environmentId='other'
            $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan);$approval.planHash=$plan.planHash
            {Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false} | Should -Throw '*different environment*'
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
        }

        It 'never executes blocked operations' {
            $plan.actions[0].classification='blocked';$plan.actions[0].operation=$null
            $plan.blockedOperations=@($plan.actions[0])
            $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan);$approval.planHash=$plan.planHash
            Mock Invoke-WpaManagerAction {throw 'must not run'}
            $result=Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false
            Should -Invoke Invoke-WpaManagerAction -Times 1 -Exactly
            $result.apply.operations.Count | Should -Be 1
            $result.apply.operations[0].id | Should -Be 'two'
        }

        It 'records reboot-required without invoking a reboot command' {
            Mock Invoke-WpaManagerAction {[pscustomobject]@{ExitCode=3010;TimedOut=$false;DurationMs=5;StdOut='';StdErr='';RebootRequired=$true}}
            Mock Test-WpaExpectedState {[pscustomobject]@{name='tool';manager='scoop';id='tool';status='verified';reasonCode='EXPECTED_STATE_PRESENT'}}
            Mock Get-WpaInventory {$inventory}
            $result=Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false
            $result.apply.rebootRequired | Should -BeTrue
            $result.apply.operations[0].reasonCode | Should -Be 'REBOOT_REQUIRED'
            $result.verify.status | Should -Be 'reboot-required'
        }

        It 'reports indeterminate post-apply verification as failed' {
            $plan.actions=@($plan.actions[0]);$plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan);$approval.planHash=$plan.planHash
            Mock Invoke-WpaManagerAction {[pscustomobject]@{ExitCode=0;TimedOut=$false;DurationMs=5;StdOut='';StdErr=''}}
            Mock Get-WpaInventory {$inventory}
            $result=Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false
            $result.verify.status | Should -Be 'failed'
            $result.verify.items[0].status | Should -Be 'indeterminate'
        }

        It 'journals before and after every attempted mutation' {
            $script:call=0
            Mock Invoke-WpaManagerAction {$script:call++;if($script:call -eq 1){[pscustomobject]@{ExitCode=0;TimedOut=$false;DurationMs=5;StdOut='';StdErr=''}}else{[pscustomobject]@{ExitCode=1;TimedOut=$false;DurationMs=5;StdOut='';StdErr='failed'}}}
            Mock Write-WpaAtomicJson {}
            $result=Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath apply.json -VerifyOutputPath $null -SummaryPath $null -Confirm:$false
            $result.apply.status | Should -Be 'partial-failure'
            Should -Invoke Write-WpaAtomicJson -ParameterFilter {$Path -eq 'apply.journal.json'} -Times 4 -Exactly
        }
    }
}
