$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent diagnostic logging boundaries' {
    InModuleScope WinPkgAgent {
        It 'redacts ANSI, controls, credentials, bearer tokens, and profile paths with a bound' {
            $text="`e[31mAuthorization: Bearer abc`e[0m`0 password=hunter2 C:\Users\alice\secret.txt " + ('x' * 5000)
            $diagnostic=ConvertTo-WpaDiagnosticText -StdOut $text -StdErr $null
            $diagnostic.text | Should -Not -Match 'abc|hunter2|alice|`e\['
            $diagnostic.text | Should -Not -Match '[\x00]'
            $diagnostic.text.Length | Should -Be 4096
            $diagnostic.truncated | Should -BeTrue
        }

        It 'hashes UTF-8 output deterministically without retaining the body' {
            $meta=Get-WpaOutputMetadata -Text 'あ'
            $repeat=Get-WpaOutputMetadata -Text 'あ'
            $meta.hash | Should -Be $repeat.hash
            $meta.hash | Should -Match '^[0-9a-f]{64}$'
            $meta.length | Should -Be 3
            $meta.truncated | Should -BeFalse
        }

        It 'does not write artifacts under WhatIf' {
            $script:policy=[pscustomobject]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch','minor');allowUninstall=$false;allowedManagers=@('scoop');allowedSources=@('main');protectedPackages=@();dangerousCategories=@('driver');requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=30;rebootHandling='record-only';unknownVersionHandling='block'}
            $fingerprint=[pscustomobject]@{manager='scoop';pathHash=('a'*64);fileSha256=('b'*64);fileVersion=$null;lastWriteTimeUtc='2026-01-01T00:00:00Z';fileLength=1;isReparsePoint=$false;signatureStatus='not-applicable';signerSubject=$null;aclAssessment='trusted'}
            $script:inventory=[pscustomobject]@{schemaVersion=1;environment=@{id='env'};status='success';managers=@(@{manager='scoop';status='success';version='1';fingerprint=$fingerprint});packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            $action=[pscustomobject]@{name='tool';manager='scoop';id='tool';source='main';classification='install';operation='install';reasonCode='PACKAGE_NOT_INSTALLED';reason='missing';risk='low';targetVersion=$null;verification=$null}
            $script:plan=[pscustomobject][ordered]@{schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z';environmentId='env';manifestHash=('a'*64);policyHash=(Get-WpaObjectHash $policy);inventoryHash=(Get-WpaInventoryStateHash $inventory);managerFingerprints=@([pscustomobject]@{manager='scoop';fingerprint=$fingerprint});actions=@($action);blockedOperations=@();warnings=@();contentHash=$null;planHash=$null}
            $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan);$plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
            $approval=[pscustomobject]@{schemaVersion=1;planId=$plan.planId;planHash=$plan.planHash;approvedAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z'}
            Mock Read-WpaJsonFile {if($Path -eq 'plan.json'){$plan}else{$approval}};Mock Test-WpaDataSchema {$true};Mock Get-WpaEnvironmentId {'env'};Mock Read-WpaPolicyFile {$policy};Mock Get-WpaInventory {$inventory};Mock Invoke-WpaManagerAction {throw 'must not run'};Mock Write-WpaAtomicJson {};Mock Write-WpaAtomicText {}
            $result=Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -WhatIf -DiagnosticLogging -OutputPath apply.json -VerifyOutputPath verify.json -SummaryPath summary.md -Confirm:$false
            $result.apply.status | Should -Be 'what-if'
            Should -Invoke Invoke-WpaManagerAction -Times 0 -Exactly
            Should -Invoke Write-WpaAtomicJson -Times 0 -Exactly
            Should -Invoke Write-WpaAtomicText -Times 0 -Exactly
        }
    }
}
