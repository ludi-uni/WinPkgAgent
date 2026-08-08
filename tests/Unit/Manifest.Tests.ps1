Describe 'repository JSON Schema contracts' {
    BeforeAll {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $schemaRoot = Join-Path $repo 'schemas'
        $fixtureRoot = Join-Path $repo 'tests/Fixtures/manifest'
        Import-Module (Join-Path $repo 'src/WinPkgAgent/WinPkgAgent.psd1') -Force
    }
    It 'parses every repository JSON schema' {
        $schemas = Get-ChildItem $schemaRoot -Filter '*.schema.json'
        $schemas | Should -Not -BeNullOrEmpty
        foreach ($schema in $schemas) {
            { Get-Content $schema.FullName -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    It 'accepts the valid manifest fixture' {
        $valid = Test-Json -Path (Join-Path $fixtureRoot 'valid.json') -SchemaFile (Join-Path $schemaRoot 'manifest.schema.json')
        $valid | Should -BeTrue
    }

    It 'rejects unsupported manager and state values' {
        $manifest = Get-Content (Join-Path $fixtureRoot 'valid.json') -Raw | ConvertFrom-Json
        $manifest.packages[0].manager = 'choco'
        $path = Join-Path $TestDrive 'bad-manager.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $path
        $managerValid = try { Test-Json -Path $path -SchemaFile (Join-Path $schemaRoot 'manifest.schema.json') -ErrorAction Stop } catch { $false }
        $managerValid | Should -BeFalse

        $manifest.packages[0].manager = 'winget'
        $manifest.packages[0].state = 'absent'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $path
        $stateValid = try { Test-Json -Path $path -SchemaFile (Join-Path $schemaRoot 'manifest.schema.json') -ErrorAction Stop } catch { $false }
        $stateValid | Should -BeFalse
    }

    It 'rejects arbitrary verification path fields' {
        $manifest = Get-Content (Join-Path $fixtureRoot 'valid.json') -Raw | ConvertFrom-Json
        $manifest.packages[0] | Add-Member -NotePropertyName verification -NotePropertyValue ([pscustomobject]@{
            commands = @([pscustomobject]@{ name = '7z'; arguments = @('--help') })
            paths = @('../outside')
        })
        $path = Join-Path $TestDrive 'bad-path.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $path
        $pathValid = try { Test-Json -Path $path -SchemaFile (Join-Path $schemaRoot 'manifest.schema.json') -ErrorAction Stop } catch { $false }
        $pathValid | Should -BeFalse
    }

    It 'rejects unsafe policy operation limits' {
        $policy = [ordered]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch');allowedManagers=@('winget');allowedSources=@('winget');protectedPackages=@();dangerousCategories=@('driver');allowUninstall=$false;requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=-1;operationTimeoutSeconds=600;rebootHandling='record-only';unknownVersionHandling='block'}
        $path = Join-Path $TestDrive 'bad-policy.json'
        $policy | ConvertTo-Json | Set-Content $path
        $policyValid = try { Test-Json -Path $path -SchemaFile (Join-Path $schemaRoot 'policy.schema.json') -ErrorAction Stop } catch { $false }
        $policyValid | Should -BeFalse
    }

    It 'accepts the schema v2 sample inventory with policy provenance' {
        $samplePath = Join-Path $repo 'examples/inventory.sample.json'
        $valid = Test-Json -Path $samplePath -SchemaFile (Join-Path $schemaRoot 'inventory.schema.json')
        $valid | Should -BeTrue
    }

    It 'rejects inventory artifacts without policy provenance' {
        $inventory = Get-Content (Join-Path $repo 'examples/inventory.sample.json') -Raw | ConvertFrom-Json
        $inventory.PSObject.Properties.Remove('policyHash')
        $path = Join-Path $TestDrive 'missing-inventory-policy.json'
        $inventory | ConvertTo-Json -Depth 10 | Set-Content $path
        (Test-Json -Path $path -SchemaFile (Join-Path $schemaRoot 'inventory.schema.json') -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'rejects an empty allowed manager scope' {
        $policy = [ordered]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch');allowedManagers=@();allowedSources=@('main');protectedPackages=@();dangerousCategories=@('driver','bios','uefi','firmware');allowUninstall=$false;requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=60;rebootHandling='record-only';unknownVersionHandling='block'}
        $path = Join-Path $TestDrive 'empty-manager-scope.json'
        $policy | ConvertTo-Json | Set-Content $path
        $policyValid = try { Test-Json -Path $path -SchemaFile (Join-Path $schemaRoot 'policy.schema.json') -ErrorAction Stop } catch { $false }
        $policyValid | Should -BeFalse

        InModuleScope WinPkgAgent -Parameters @{ Policy=$policy } {
            param($Policy)
            { Test-WpaPolicyObject -Policy ([pscustomobject]$Policy) } | Should -Throw '*manager*'
        }
    }

    It 'rejects a policy with no allowedManagers property' {
        InModuleScope WinPkgAgent {
            $policy = [pscustomobject]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch');allowedSources=@('main');protectedPackages=@();dangerousCategories=@('driver','bios','uefi','firmware');allowUninstall=$false;requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=60;rebootHandling='record-only';unknownVersionHandling='block'}
            { Test-WpaPolicyObject -Policy $policy } | Should -Throw '*manager*'
        }
    }

    It 'rejects a policy with a null allowedManagers property' {
        InModuleScope WinPkgAgent {
            $policy = [pscustomobject]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch');allowedManagers=$null;allowedSources=@('main');protectedPackages=@();dangerousCategories=@('driver','bios','uefi','firmware');allowUninstall=$false;requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=60;rebootHandling='record-only';unknownVersionHandling='block'}
            { Test-WpaPolicyObject -Policy $policy } | Should -Throw '*manager*'
        }
    }

    It 'rejects an ordered-dictionary policy with no allowedManagers key' {
        InModuleScope WinPkgAgent {
            $policy = [ordered]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch');allowedManagers=@('scoop');allowedSources=@('main');protectedPackages=@();dangerousCategories=@('driver','bios','uefi','firmware');allowUninstall=$false;requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=60;rebootHandling='record-only';unknownVersionHandling='block'}
            $policy.Remove('allowedManagers')
            { Test-WpaPolicyObject -Policy $policy } | Should -Throw '*manager*'
        }
    }

    It 'rejects an ordered-dictionary policy with a null allowedManagers value' {
        InModuleScope WinPkgAgent {
            $policy = [ordered]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch');allowedManagers=$null;allowedSources=@('main');protectedPackages=@();dangerousCategories=@('driver','bios','uefi','firmware');allowUninstall=$false;requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=60;rebootHandling='record-only';unknownVersionHandling='block'}
            { Test-WpaPolicyObject -Policy $policy } | Should -Throw '*manager*'
        }
    }
}

Describe 'manifest semantic validation contract' {
    BeforeAll {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $fixtureRoot = Join-Path $repo 'tests/Fixtures/manifest'
        Import-Module (Join-Path $repo 'src/WinPkgAgent/WinPkgAgent.psd1') -Force
    }
    It 'rejects duplicate logical names' {
        InModuleScope WinPkgAgent -Parameters @{ FixtureRoot=$fixtureRoot } {
            param($FixtureRoot)
            $manifest = Get-Content (Join-Path $FixtureRoot 'duplicate-name.json') -Raw | ConvertFrom-Json
            { Test-WpaManifestObject -Manifest $manifest } | Should -Throw
        }
    }

    It 'rejects duplicate manager and id ownership' {
        InModuleScope WinPkgAgent -Parameters @{ FixtureRoot=$fixtureRoot } {
            param($FixtureRoot)
            $manifest = Get-Content (Join-Path $FixtureRoot 'duplicate-manager-id.json') -Raw | ConvertFrom-Json
            { Test-WpaManifestObject -Manifest $manifest } | Should -Throw
        }
    }

    It 'rejects a manifest missing schemaVersion' {
        $manifest = Get-Content (Join-Path $fixtureRoot 'valid.json') -Raw | ConvertFrom-Json
        $manifest.PSObject.Properties.Remove('schemaVersion')
        $path = Join-Path $TestDrive 'missing-schema-version.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $path
        $result = Test-WpaManifest -Path $path
        $result.valid | Should -BeFalse
    }

    It 'rejects an invalid package identifier' {
        InModuleScope WinPkgAgent -Parameters @{ FixtureRoot=$fixtureRoot } {
            param($FixtureRoot)
            $manifest = Get-Content (Join-Path $FixtureRoot 'valid.json') -Raw | ConvertFrom-Json
            $manifest.packages[0].id = 'unsafe;command'
            { Test-WpaManifestObject -Manifest $manifest } | Should -Throw
        }
    }

    It 'rejects malformed JSON and malformed YAML input' {
        $jsonPath = Join-Path $TestDrive 'malformed.json'
        Set-Content $jsonPath '{ not-json'
        InModuleScope WinPkgAgent -Parameters @{ JsonPath=$jsonPath } { param($JsonPath); { Read-WpaJsonFile -Path $JsonPath } | Should -Throw }

        $yamlPath = Join-Path $TestDrive 'malformed.yaml'
        Set-Content $yamlPath "schemaVersion: 1`npackages: [`n"
        $result = Test-WpaManifest -Path $yamlPath
        $result.valid | Should -BeFalse
    }

    It 'enforces the bounded input size limit' {
        $path = Join-Path $TestDrive 'oversized.txt'
        Set-Content $path ('x' * 32)
        InModuleScope WinPkgAgent -Parameters @{ InputPath=$path } { param($InputPath); { Read-WpaTextFile -Path $InputPath -MaxBytes 8 } | Should -Throw }
    }

    It 'rejects unknown policy values' {
        InModuleScope WinPkgAgent {
            $policy = [pscustomobject]@{ schemaVersion = 1; allowUninstall = $false; requireApproval = $true; unknownVersionHandling = 'allow'; rejectStateChanges = $true; rebootHandling = 'record-only'; maxOperations = 10; operationTimeoutSeconds = 60 }
            { Test-WpaPolicyObject -Policy $policy } | Should -Throw
        }
    }

    It 'rejects arbitrary-code verification configuration' {
        InModuleScope WinPkgAgent -Parameters @{ FixtureRoot=$fixtureRoot } {
            param($FixtureRoot)
            $manifest = Get-Content (Join-Path $FixtureRoot 'valid.json') -Raw | ConvertFrom-Json
            $manifest.packages[0] | Add-Member -NotePropertyName verification -NotePropertyValue ([pscustomobject]@{ command = 'pwsh'; arguments = @('-Command','Get-Process') })
            { Test-WpaManifestObject -Manifest $manifest } | Should -Throw
        }
    }

    It 'requires an explicit source and category for every package' {
        $schemaRoot = Join-Path ((Resolve-Path (Join-Path $PSScriptRoot '../..')).Path) 'schemas'
        $manifest = Get-Content (Join-Path $fixtureRoot 'valid.json') -Raw | ConvertFrom-Json
        $manifest.packages[0].PSObject.Properties.Remove('source')
        $manifest.packages[0].PSObject.Properties.Remove('category')
        $path = Join-Path $TestDrive 'missing-source-category.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content $path
        (Test-Json -Path $path -SchemaFile (Join-Path $schemaRoot 'manifest.schema.json') -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'does not allow policy relaxation for major upgrades or dangerous categories' {
        InModuleScope WinPkgAgent {
            $policy = [pscustomobject]@{ schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch','major');allowUninstall=$false;allowedManagers=@('winget');allowedSources=@('winget');protectedPackages=@();dangerousCategories=@();requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=60;rebootHandling='record-only';unknownVersionHandling='block' }
            { Test-WpaPolicyObject -Policy $policy } | Should -Throw
        }
    }

    It 'validates the explicit manager policy samples through the policy reader' {
        $configRoot = Join-Path ((Resolve-Path (Join-Path $PSScriptRoot '../..')).Path) 'config'
        InModuleScope WinPkgAgent -Parameters @{ ConfigRoot=$configRoot } {
            param($ConfigRoot)
            $codex = Read-WpaPolicyFile -Path (Join-Path $ConfigRoot 'policy.codex.yaml')
            @($codex.allowedManagers) | Should -BeExactly @('scoop')
            @($codex.allowedSources) | Should -BeExactly @('main','extras','versions')
            $desktop = Read-WpaPolicyFile -Path (Join-Path $ConfigRoot 'policy.desktop.yaml')
            @($desktop.allowedManagers) | Should -BeExactly @('winget','scoop')
            @($desktop.allowedSources) | Should -BeExactly @('winget','main','extras','versions')
        }
    }
}
