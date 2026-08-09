$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent planning' {
    InModuleScope WinPkgAgent {
        BeforeEach {
            $script:policy = [pscustomobject]@{
                schemaVersion=1; allowInstall=$true; allowUpgrade=@('patch','minor'); allowUninstall=$false
                allowedManagers=@('winget','scoop'); allowedSources=@('winget','main','extras','versions')
                protectedPackages=@(); dangerousCategories=@('driver','bios','uefi','firmware')
                requireApproval=$true; approvalValidityMinutes=30; rejectStateChanges=$true
                maxOperations=10; operationTimeoutSeconds=600; rebootHandling='record-only'; unknownVersionHandling='block'
            }
        }

        It 'builds a file-free plan object from resolved inputs with stable hash fields' {
            $manifest = [pscustomobject]@{ packages=@([pscustomobject]@{ name='vscode'; manager='winget'; id='Microsoft.VisualStudioCode'; state='present'; version='latest'; source='winget' }) }
            $fingerprint = [pscustomobject]@{
                manager='winget'; pathHash=('a'*64); fileSha256=('b'*64); fileVersion=$null
                lastWriteTimeUtc='2026-01-01T00:00:00Z'; fileLength=7; isReparsePoint=$false
                signatureStatus='valid'; signerSubject='fixture'; aclAssessment='trusted'
            }
            $policyHash = Get-WpaObjectHash $policy
            $inventory = [pscustomobject]@{
                schemaVersion=2; policyHash=$policyHash; managerScope=@('winget'); status='success'
                environment=[pscustomobject]@{ id='env' }
                managers=@([pscustomobject]@{ manager='winget'; status='success'; version='1'; fingerprint=$fingerprint })
                packages=@(); warnings=@(); collectedAt='2026-01-01T00:00:00Z'
            }
            $now = [datetimeoffset]'2026-01-02T03:04:05+00:00'
            Mock Read-WpaManifestResolved { throw 'FILE_READ_GUARD: manifest reader invoked' }
            Mock Read-WpaPolicyFile { throw 'FILE_READ_GUARD: policy reader invoked' }
            Mock Read-WpaJsonFile { throw 'FILE_READ_GUARD: inventory reader invoked' }
            Mock Write-WpaAtomicJson { throw 'FILE_WRITE_GUARD: JSON writer invoked' }
            Mock Write-WpaAtomicText { throw 'FILE_WRITE_GUARD: text writer invoked' }

            $plan = New-WpaPlanObject -Manifest $manifest -Policy $policy -Inventory $inventory -Now $now

            $plan.schemaVersion | Should -Be 1
            $plan.toolVersion | Should -Be '0.1.0'
            $plan.environmentId | Should -Be 'env'
            $plan.createdAt | Should -Be '2026-01-02T03:04:05.0000000+00:00'
            $plan.expiresAt | Should -Be '2026-01-02T03:34:05.0000000+00:00'
            $plan.actions[0].reasonCode | Should -Be 'PACKAGE_NOT_INSTALLED'
            $plan.managerFingerprints[0].fingerprint.manager | Should -Be 'winget'
            $plan.manifestHash | Should -Match '^[a-f0-9]{64}$'
            $plan.policyHash | Should -Match '^[a-f0-9]{64}$'
            $plan.inventoryHash | Should -Match '^[a-f0-9]{64}$'
            $plan.contentHash | Should -Match '^[a-f0-9]{64}$'
            $plan.planHash | Should -Match '^[a-f0-9]{64}$'
            Assert-MockCalled Read-WpaManifestResolved -Times 0
            Assert-MockCalled Read-WpaPolicyFile -Times 0
            Assert-MockCalled Read-WpaJsonFile -Times 0
            Assert-MockCalled Write-WpaAtomicJson -Times 0
            Assert-MockCalled Write-WpaAtomicText -Times 0
        }

        It 'plans an install with a stable reason code' {
            $manifest = [pscustomobject]@{ packages=@([pscustomobject]@{ name='vscode'; manager='winget'; id='Microsoft.VisualStudioCode'; state='present'; version='latest'; source='winget' }) }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='winget';status='success';version='1'}); packages=@() }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions[0].classification | Should -Be 'install'
            $evaluation.actions[0].reasonCode | Should -Be 'PACKAGE_NOT_INSTALLED'
        }

        It 'blocks a major upgrade' {
            $manifest = [pscustomobject]@{ packages=@([pscustomobject]@{ name='tool'; manager='scoop'; id='tool'; state='present'; version='latest'; source='main' }) }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='scoop';status='success';version='1'}); packages=@([pscustomobject]@{manager='scoop';id='tool';displayName='Tool';installedVersion='1.9.0';availableVersion='2.0.0';source='main';scope='user'}) }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions[0].classification | Should -Be 'blocked'
            $evaluation.actions[0].reasonCode | Should -Be 'MAJOR_UPGRADE_BLOCKED'
        }

        It 'classifies no-op, patch, and minor upgrades' {
            $manifest = [pscustomobject]@{ packages=@(
                [pscustomobject]@{ name='same'; manager='winget'; id='Vendor.Same'; state='present'; version='latest'; source='winget' },
                [pscustomobject]@{ name='patch'; manager='winget'; id='Vendor.Patch'; state='present'; version='latest'; source='winget' },
                [pscustomobject]@{ name='minor'; manager='winget'; id='Vendor.Minor'; state='present'; version='latest'; source='winget' }
            ) }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='winget';status='success';version='1'}); packages=@(
                [pscustomobject]@{manager='winget';id='Vendor.Same';displayName='Same';installedVersion='1.0.0';availableVersion='1.0.0';source='winget';scope='user'},
                [pscustomobject]@{manager='winget';id='Vendor.Patch';displayName='Patch';installedVersion='1.0.0';availableVersion='1.0.1';source='winget';scope='user'},
                [pscustomobject]@{manager='winget';id='Vendor.Minor';displayName='Minor';installedVersion='1.0.0';availableVersion='1.1.0';source='winget';scope='user'}
            ) }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions.classification | Should -Be @('no-op','upgrade','upgrade')
            $evaluation.actions.reasonCode | Should -Be @('VERSION_ALREADY_SATISFIED','PATCH_UPGRADE_AVAILABLE','MINOR_UPGRADE_AVAILABLE')
        }

        It 'blocks an unparseable version, a disallowed source, and a protected package' {
            $policy.protectedPackages=@('protected')
            $manifest = [pscustomobject]@{ packages=@(
                [pscustomobject]@{ name='unknown'; manager='scoop'; id='unknown'; state='present'; version='latest'; source='main' },
                [pscustomobject]@{ name='source'; manager='scoop'; id='source'; state='present'; version='latest'; source='untrusted' },
                [pscustomobject]@{ name='protected'; manager='scoop'; id='protected'; state='present'; version='latest'; source='main' }
            ) }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='scoop';status='success';version='1'}); packages=@(
                [pscustomobject]@{manager='scoop';id='unknown';displayName='Unknown';installedVersion='rolling';availableVersion='next';source='main';scope='user'},
                [pscustomobject]@{manager='scoop';id='source';displayName='Source';installedVersion='1.0.0';availableVersion='1.0.1';source='untrusted';scope='user'},
                [pscustomobject]@{manager='scoop';id='protected';displayName='Protected';installedVersion='1.0.0';availableVersion='1.0.1';source='main';scope='user'}
            ) }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions.reasonCode | Should -Be @('UNPARSEABLE_VERSION_BLOCKED','SOURCE_NOT_ALLOWED','PROTECTED_PACKAGE')
            @($evaluation.blockedOperations).Count | Should -Be 3
        }

        It 'blocks packages whose manager inventory is incomplete' {
            $manifest = [pscustomobject]@{ packages=@([pscustomobject]@{ name='tool'; manager='scoop'; id='tool'; state='present'; version='latest'; source='main' }) }
            $inventory = [pscustomobject]@{ status='partial'; environment=@{id='env'}; managers=@(@{manager='scoop';status='partial';version='1'}); packages=@() }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions[0].reasonCode | Should -Be 'MANAGER_UNAVAILABLE'
        }

        It 'blocks a disallowed manager before inventory lookup or fingerprint evidence' {
            $policy.allowedManagers=@('scoop')
            $manifest = [pscustomobject]@{ packages=@([pscustomobject]@{ name='vscode'; manager='winget'; id='Microsoft.VisualStudioCode'; state='present'; version='latest'; source='winget' }) }
            $inventory = [pscustomobject]@{ schemaVersion=2; policyHash=('a'*64); managerScope=@('scoop'); status='success'; environment=@{id='env'}; managers=@(); packages=@() }
            Mock Assert-WpaManagerFingerprintEvidence { throw 'fingerprint must not be checked' }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions[0].classification | Should -Be 'blocked'
            $evaluation.actions[0].operation | Should -BeNullOrEmpty
            $evaluation.actions[0].reasonCode | Should -Be 'MANAGER_NOT_ALLOWED'
            Assert-MockCalled Assert-WpaManagerFingerprintEvidence -Times 0
        }

        It 'always blocks driver and firmware categories' {
            $policy.dangerousCategories=@()
            $manifest = [pscustomobject]@{ packages=@(
                [pscustomobject]@{ name='driver'; manager='winget'; id='Vendor.Driver'; state='present'; version='latest'; source='winget'; category='driver' },
                [pscustomobject]@{ name='firmware'; manager='winget'; id='Vendor.Firmware'; state='present'; version='latest'; source='winget'; category='firmware' }
            ) }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='winget';status='success';version='1'}); packages=@() }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions.reasonCode | Should -Be @('DANGEROUS_CATEGORY_BLOCKED','DANGEROUS_CATEGORY_BLOCKED')
        }

        It 'blocks Scoop upgrades because its official update command cannot pin the approved version' {
            $manifest = [pscustomobject]@{ packages=@([pscustomobject]@{ name='tool'; manager='scoop'; id='tool'; state='present'; version='latest'; source='main';category='cli' }) }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='scoop';status='success';version='1'}); packages=@([pscustomobject]@{manager='scoop';id='tool';displayName='Tool';installedVersion='1.0.0';availableVersion='1.0.1';source='main';scope='user'}) }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions[0].classification | Should -Be 'blocked'
            $evaluation.actions[0].reasonCode | Should -Be 'SCOOP_TARGET_VERSION_UNENFORCEABLE'
        }

        It 'renders every execution-relevant field in the human plan' {
            $plan=[pscustomobject]@{planId='p';contentHash=('a'*64);planHash=('b'*64);expiresAt='2099-01-01T00:00:00Z';warnings=@();actions=@([pscustomobject]@{name='tool';manager='winget';id='Vendor.Tool';source='winget';classification='upgrade';operation='upgrade';risk='medium';reasonCode='PATCH_UPGRADE_AVAILABLE';reason='update';targetVersion='1.0.1';verification=[pscustomobject]@{command='tool';arguments=@('--version')}})}
            $markdown=ConvertTo-WpaPlanMarkdown $plan
            $markdown | Should -Match 'Vendor\.Tool'
            $markdown | Should -Match 'winget'
            $markdown | Should -Match '1\.0\.1'
            $markdown | Should -Match 'tool --version'
        }

        It 'renders a plan when optional blocked operations are omitted' {
            $plan=[pscustomobject]@{planId='p';expiresAt='2099-01-01T00:00:00Z';actions=@();warnings=@()}
            { ConvertTo-WpaPlanMarkdown $plan } | Should -Not -Throw
            (ConvertTo-WpaPlanMarkdown $plan) | Should -Match 'Blocked: 0'
        }

        It 'renders incomplete action fixtures without optional property exceptions' {
            $plan=[pscustomobject]@{planId='p';expiresAt='2099-01-01T00:00:00Z';actions=@([pscustomobject]@{name='tool';manager='scoop';id='tool';classification='unknown';reasonCode='UNKNOWN_PACKAGE';risk='low'});warnings=@()}
            { ConvertTo-WpaPlanMarkdown $plan } | Should -Not -Throw
        }

        It 'rejects incomplete inventory fingerprints while creating a plan' {
            $manifest=[pscustomobject]@{packages=@([pscustomobject]@{name='tool';manager='scoop';id='tool';state='present';version='latest';source='main'})}
            $inventory=[pscustomobject]@{schemaVersion=2;policyHash=(Get-WpaObjectHash $policy);managerScope=@('scoop');environment=@{id='env'};status='success';managers=@([pscustomobject]@{manager='scoop';status='success';version='1';fingerprint=[pscustomobject]@{manager='scoop';signatureStatus='not-applicable';aclAssessment=$null}});packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaManifestResolved {$manifest};Mock Test-WpaManifestObject {$true};Mock Read-WpaPolicyFile {$policy};Mock Read-WpaJsonFile {$inventory};Mock Test-WpaDataSchema {$true}
            { New-WpaPlan -ManifestPath manifest.yaml -PolicyPath policy.yaml -InventoryPath inventory.json -OutputPath plan.json -WhatIf } | Should -Throw '*MANAGER_FINGERPRINT_UNAVAILABLE*'
        }

        It 'rejects an inventory policy hash mismatch before fingerprint lookup' {
            $manifest=[pscustomobject]@{packages=@([pscustomobject]@{name='tool';manager='scoop';id='tool';state='present';version='latest';source='main'})}
            $inventory=[pscustomobject]@{schemaVersion=2;policyHash=('a'*64);managerScope=@('scoop');environment=@{id='env'};status='success';managers=@([pscustomobject]@{manager='scoop';status='success';version='1';fingerprint=[pscustomobject]@{manager='scoop';signatureStatus='valid';aclAssessment='trusted'}});packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaManifestResolved {$manifest};Mock Test-WpaManifestObject {$true};Mock Read-WpaPolicyFile {$policy};Mock Read-WpaJsonFile {$inventory};Mock Test-WpaDataSchema {$true}
            Mock Assert-WpaManagerFingerprintEvidence { throw 'fingerprint must not be checked' }
            { New-WpaPlan -ManifestPath manifest.yaml -PolicyPath policy.yaml -InventoryPath inventory.json -OutputPath plan.json -WhatIf } | Should -Throw 'INVENTORY_SCOPE_MISMATCH'
            Assert-MockCalled Assert-WpaManagerFingerprintEvidence -Times 0
        }

        It 'rejects an allowed manifest manager missing from inventory scope' {
            $manifest=[pscustomobject]@{packages=@([pscustomobject]@{name='tool';manager='scoop';id='tool';state='present';version='latest';source='main'})}
            $inventory=[pscustomobject]@{schemaVersion=2;policyHash=(Get-WpaObjectHash $policy);managerScope=@('winget');environment=@{id='env'};status='success';managers=@();packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaManifestResolved {$manifest};Mock Test-WpaManifestObject {$true};Mock Read-WpaPolicyFile {$policy};Mock Read-WpaJsonFile {$inventory};Mock Test-WpaDataSchema {$true}
            { New-WpaPlan -ManifestPath manifest.yaml -PolicyPath policy.yaml -InventoryPath inventory.json -OutputPath plan.json -WhatIf } | Should -Throw 'INVENTORY_SCOPE_MISMATCH'
        }

        It 'does not fingerprint a disallowed package when its manager is absent' {
            $policy.allowedManagers=@('scoop')
            $manifest=[pscustomobject]@{packages=@([pscustomobject]@{name='vscode';manager='winget';id='Microsoft.VisualStudioCode';state='present';version='latest';source='winget'})}
            $inventory=[pscustomobject]@{schemaVersion=2;policyHash=(Get-WpaObjectHash $policy);managerScope=@('scoop');environment=@{id='env'};status='success';managers=@();packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaManifestResolved {$manifest};Mock Test-WpaManifestObject {$true};Mock Read-WpaPolicyFile {$policy};Mock Read-WpaJsonFile {$inventory};Mock Test-WpaDataSchema {$true}
            Mock Assert-WpaManagerFingerprintEvidence { throw 'fingerprint must not be checked' }
            $plan=New-WpaPlan -ManifestPath manifest.yaml -PolicyPath policy.yaml -InventoryPath inventory.json -OutputPath plan.json -WhatIf
            $plan.actions[0].reasonCode | Should -Be 'MANAGER_NOT_ALLOWED'
            Assert-MockCalled Assert-WpaManagerFingerprintEvidence -Times 0
        }

        It 'plans a winget action when an unrelated scoop fingerprint is untrusted' {
            $manifest=[pscustomobject]@{packages=@([pscustomobject]@{name='vscode';manager='winget';id='Microsoft.VisualStudioCode';state='present';version='latest';source='winget'})}
            $wingetFingerprint=[pscustomobject]@{manager='winget';signatureStatus='valid';aclAssessment='trusted'}
            $scoopFingerprint=[pscustomobject]@{manager='scoop';signatureStatus='not-applicable';aclAssessment='unknown'}
            $inventory=[pscustomobject]@{schemaVersion=2;policyHash=(Get-WpaObjectHash $policy);managerScope=@('winget');environment=@{id='env'};status='success';managers=@(
                [pscustomobject]@{manager='winget';status='success';version='1';fingerprint=$wingetFingerprint},
                [pscustomobject]@{manager='scoop';status='unavailable';version=$null;fingerprint=$scoopFingerprint}
            );packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaManifestResolved {$manifest};Mock Test-WpaManifestObject {$true};Mock Read-WpaPolicyFile {$policy};Mock Read-WpaJsonFile {$inventory};Mock Test-WpaDataSchema {$true}
            $plan=New-WpaPlan -ManifestPath manifest.yaml -PolicyPath policy.yaml -InventoryPath inventory.json -OutputPath plan.json -WhatIf
            $plan.actions[0].manager | Should -Be 'winget'
            $plan.actions[0].classification | Should -Be 'install'
            @($plan.managerFingerprints).Count | Should -Be 2
        }

        It 'blocks a scoop action when the declared scoop fingerprint is untrusted' {
            $manifest=[pscustomobject]@{packages=@([pscustomobject]@{name='tool';manager='scoop';id='tool';state='present';version='latest';source='main'})}
            $wingetFingerprint=[pscustomobject]@{manager='winget';signatureStatus='valid';aclAssessment='trusted'}
            $scoopFingerprint=[pscustomobject]@{manager='scoop';signatureStatus='not-applicable';aclAssessment='unknown'}
            $inventory=[pscustomobject]@{schemaVersion=2;policyHash=(Get-WpaObjectHash $policy);managerScope=@('scoop');environment=@{id='env'};status='success';managers=@(
                [pscustomobject]@{manager='winget';status='success';version='1';fingerprint=$wingetFingerprint},
                [pscustomobject]@{manager='scoop';status='unavailable';version=$null;fingerprint=$scoopFingerprint}
            );packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            Mock Read-WpaManifestResolved {$manifest};Mock Test-WpaManifestObject {$true};Mock Read-WpaPolicyFile {$policy};Mock Read-WpaJsonFile {$inventory};Mock Test-WpaDataSchema {$true}
            { New-WpaPlan -ManifestPath manifest.yaml -PolicyPath policy.yaml -InventoryPath inventory.json -OutputPath plan.json -WhatIf } | Should -Throw '*MANAGER_PATH_UNTRUSTED: scoop*'
        }

        It 'blocks all mutations when the maximum operation count is exceeded' {
            $policy.maxOperations=1
            $manifest = [pscustomobject]@{ packages=@(
                [pscustomobject]@{ name='one'; manager='scoop'; id='one'; state='present'; version='latest'; source='main' },
                [pscustomobject]@{ name='two'; manager='scoop'; id='two'; state='present'; version='latest'; source='main' }
            ) }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='scoop';status='success';version='1'}); packages=@() }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions.classification | Should -Be @('blocked','blocked')
            $evaluation.actions.reasonCode | Should -Be @('MAX_OPERATIONS_EXCEEDED','MAX_OPERATIONS_EXCEEDED')
        }

        It 'reports undeclared packages without uninstall actions' {
            $manifest = [pscustomobject]@{ packages=@() }
            $inventory = [pscustomobject]@{ status='success'; environment=@{id='env'}; managers=@(@{manager='winget';status='success';version='1'}); packages=@([pscustomobject]@{manager='winget';id='Vendor.App';displayName='App';installedVersion='1';source='winget';scope='user'}) }
            $evaluation = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
            $evaluation.actions[0].classification | Should -Be 'unmanaged'
            $evaluation.actions[0].reasonCode | Should -Be 'UNMANAGED_PACKAGE_REPORTED'
            ($evaluation.actions.operation -contains 'uninstall') | Should -BeFalse
        }

        It 'produces a deterministic content hash with different metadata' {
            $base=[ordered]@{schemaVersion=1;toolVersion='0.1.0';environmentId='env';manifestHash=('a'*64);policyHash=('b'*64);inventoryHash=('c'*64);actions=@();blockedOperations=@();warnings=@()}
            $first=[pscustomobject]([ordered]@{planId='first';createdAt='2026-01-01T00:00:00Z';expiresAt='2026-01-01T01:00:00Z'}+$base)
            $second=[pscustomobject]([ordered]@{planId='second';createdAt='2026-02-01T00:00:00Z';expiresAt='2026-02-01T01:00:00Z'}+$base)
            (Get-WpaObjectHash (Get-WpaPlanContent $first)) | Should -Be (Get-WpaObjectHash (Get-WpaPlanContent $second))
        }
    }
}
