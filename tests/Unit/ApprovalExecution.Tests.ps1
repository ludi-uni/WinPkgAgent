$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent plan approval and execution gates' {
    InModuleScope WinPkgAgent {
        It 'rejects a tampered plan hash' {
            $plan = [pscustomobject]@{ schemaVersion=1; planId='p'; contentHash='c'; planHash='bad'; actions=@() }
            { Assert-WpaPlanIntegrity -Plan $plan } | Should -Throw
        }

        It 'rejects an expired approval' {
            $approval = [pscustomobject]@{ schemaVersion=1; planId='p'; planHash=('a' * 64); approvedAt='2026-01-01T00:00:00Z'; expiresAt='2026-01-01T00:01:00Z' }
            { Assert-WpaApproval -Approval $approval -PlanId 'p' -PlanHash ('a' * 64) -Now ([datetimeoffset]'2026-01-02T00:00:00Z') } | Should -Throw
        }

        It 'accepts only an approval for the exact plan digest' {
            $approval = [pscustomobject]@{ schemaVersion=1; planId='p'; planHash=('a' * 64); approvedAt='2026-01-01T00:00:00Z'; expiresAt='2026-01-02T00:00:00Z' }
            { Assert-WpaApproval -Approval $approval -PlanId 'p' -PlanHash ('b' * 64) -Now ([datetimeoffset]'2026-01-01T00:30:00Z') } | Should -Throw
        }

        It 'does not expose a force or approval bypass parameter' {
            $parameters = (Get-Command Invoke-WpaPlan).Parameters.Keys
            $parameters | Should -Not -Contain 'Force'
            $parameters | Should -Not -Contain 'Approve'
            $parameters | Should -Not -Contain 'SkipApproval'
        }

        It 'runs zero mutating adapter calls under WhatIf' {
            $action=[pscustomobject]@{name='tool';manager='scoop';id='tool';source='main';classification='install';operation='install';reasonCode='PACKAGE_NOT_INSTALLED';reason='missing';risk='low';targetVersion=$null;verification=$null}
            $plan=[pscustomobject][ordered]@{schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z';environmentId='env';manifestHash=('a'*64);policyHash=$null;inventoryHash=$null;actions=@($action);blockedOperations=@();warnings=@();contentHash=$null;planHash=$null}
            $policy=[pscustomobject]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch','minor');allowUninstall=$false;allowedManagers=@('winget','scoop');allowedSources=@('winget','main');protectedPackages=@();dangerousCategories=@('driver');requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=600;rebootHandling='record-only';unknownVersionHandling='block'}
            $inventory=[pscustomobject]@{schemaVersion=1;environment=@{id='env'};status='success';managers=@(@{manager='scoop';status='success';version='1'});packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            $plan.policyHash=Get-WpaObjectHash $policy;$plan.inventoryHash=Get-WpaInventoryStateHash $inventory;$plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
            $approval=[pscustomobject]@{schemaVersion=1;planId=$plan.planId;planHash=$plan.planHash;approvedAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z'}
            Mock Read-WpaJsonFile { if($Path -eq 'plan.json'){$plan}else{$approval} }
            Mock Test-WpaDataSchema { $true };Mock Get-WpaEnvironmentId {'env'};Mock Read-WpaPolicyFile {$policy};Mock Get-WpaInventory {$inventory};Mock Invoke-WpaManagerAction {throw 'must not run'}
            $result=Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -WhatIf -Confirm:$false
            $result.apply.status | Should -Be 'what-if'
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
        }

        It 'rejects unsafe verification and mismatched classification-operation pairs in a plan' {
            $mismatch=[pscustomobject]@{name='tool';manager='scoop';id='tool';source='main';classification='install';operation='upgrade';reasonCode='PACKAGE_NOT_INSTALLED';reason='missing';risk='low';targetVersion=$null;verification=$null}
            { Assert-WpaPlanActionSet -Actions @($mismatch) } | Should -Throw '*classification*'
            $unsafe=[pscustomobject]@{name='tool';manager='scoop';id='tool';source='main';classification='install';operation='install';reasonCode='PACKAGE_NOT_INSTALLED';reason='missing';risk='low';targetVersion=$null;verification=[pscustomobject]@{command='pwsh';arguments=@('-Command','Get-Process')}}
            { Assert-WpaPlanActionSet -Actions @($unsafe) } | Should -Throw '*Shells*'
            $scoopUpgrade=[pscustomobject]@{name='tool';manager='scoop';id='tool';source='main';classification='upgrade';operation='upgrade';reasonCode='PATCH_UPGRADE_AVAILABLE';reason='update';risk='medium';targetVersion='1.0.1';verification=$null}
            { Assert-WpaPlanActionSet -Actions @($scoopUpgrade) } | Should -Throw '*Scoop upgrades*'
        }

        It 'rejects a changed manager fingerprint before mutation' {
            $fingerprint=[pscustomobject]@{manager='scoop';pathHash=('a'*64);fileSha256=('b'*64);fileVersion=$null;lastWriteTimeUtc='2026-01-01T00:00:00Z';fileLength=1;isReparsePoint=$false;signatureStatus='not-applicable';signerSubject=$null;aclAssessment='trusted'}
            $inventory.managers[0].fingerprint=$fingerprint;$plan.inventoryHash=Get-WpaInventoryStateHash $inventory;$plan.managerFingerprints=@([pscustomobject]@{manager='scoop';fingerprint=$fingerprint});$plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan);$approval.planHash=$plan.planHash
            $changed=$fingerprint.PSObject.Copy();$changed.fileSha256=('c'*64)
            Mock Get-WpaInventory {$inventory.PSObject.Copy()};$inventory.managers[0].fingerprint=$changed;Mock Invoke-WpaManagerAction {throw 'must not run'}
            { Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false } | Should -Throw '*MANAGER_EXECUTABLE_CHANGED*'
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
        }

        It 'keeps unavailable fingerprints distinct from invalid signatures' {
            $fingerprint=[pscustomobject]@{manager='scoop';pathHash=('a'*64);fileSha256=('b'*64);fileVersion=$null;lastWriteTimeUtc='2026-01-01T00:00:00Z';fileLength=1;isReparsePoint=$false;signatureStatus='not-applicable';signerSubject=$null;aclAssessment='trusted'}
            $inventory.managers[0].fingerprint=$fingerprint;$plan.inventoryHash=Get-WpaInventoryStateHash $inventory;$plan.managerFingerprints=@([pscustomobject]@{manager='scoop';fingerprint=$fingerprint});$plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan);$approval.planHash=$plan.planHash
            $inventory.managers[0].fingerprint=$null;Mock Get-WpaInventory {$inventory.PSObject.Copy()};Mock Invoke-WpaManagerAction {throw 'must not run'}
            { Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false } | Should -Throw '*MANAGER_FINGERPRINT_UNAVAILABLE*'
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
        }
    }
}
