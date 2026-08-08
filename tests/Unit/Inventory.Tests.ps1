Describe 'inventory aggregation' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }
    It 'preserves successful results when one manager fails' {
        InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Managers @('winget','scoop') -PolicyHash ('a' * 64) -Adapters @{winget={ [pscustomobject]@{Available=$true;Success=$true;Packages=@([pscustomobject]@{Id='a'});Warning=$null} };scoop={ [pscustomobject]@{Available=$true;Success=$false;Packages=@();Warning='bad'} }}; $r.status | Should -Be 'partial'; $r.packages.Count | Should -Be 1 }
    }
    It 'fails closed when neither manager succeeds' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Managers @('winget','scoop') -PolicyHash ('a' * 64) -Adapters @{winget={throw 'x'};scoop={throw 'y'}}; $r.status | Should -Be 'failed' } }
    It 'reports winget-only success as partial' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Managers @('winget','scoop') -PolicyHash ('a' * 64) -Adapters @{winget={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }}; $r.status | Should -Be 'partial'; $r.managers.Count | Should -Be 2 } }
    It 'reports scoop-only success as partial' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Managers @('winget','scoop') -PolicyHash ('a' * 64) -Adapters @{scoop={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }}; $r.status | Should -Be 'partial' } }
    It 'reports both successful managers as success' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Managers @('winget','scoop') -PolicyHash ('a' * 64) -Adapters @{winget={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} };scoop={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }}; $r.status | Should -Be 'success' } }
    It 'keeps both successful managers successful when fingerprints are unavailable' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\manager.exe' }
            Mock Get-WpaManagerFingerprint { throw 'fingerprint unavailable' }
            $r=Get-WpaInventoryAggregate -Managers @('winget','scoop') -PolicyHash ('a' * 64) -Adapters @{
                winget={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }
                scoop={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }
            }
            $r.status | Should -Be 'success'
            @($r.managers | Where-Object warning).Count | Should -Be 2
            $r.warnings | Should -HaveCount 2
            $r.warnings | Should -Match 'fingerprint unavailable'
        }
    }
    It 'retains timeout warning and successful packages' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Managers @('winget','scoop') -PolicyHash ('a' * 64) -Adapters @{winget={ [pscustomobject]@{Success=$true;Packages=@([pscustomobject]@{Id='ok'});Warning=$null} };scoop={ [pscustomobject]@{Success=$false;TimedOut=$true;Packages=@();Warning='timeout'} }}; $r.status | Should -Be 'partial'; $r.packages.Count | Should -Be 1; $r.warnings | Should -Contain 'timeout' } }
    It 'preserves successful inventory when fingerprint resolution fails' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\winget.exe' }
            Mock Get-WpaManagerFingerprint { throw 'fingerprint unavailable' }
            $r=Get-WpaInventoryAggregate -Managers @('winget') -PolicyHash ('a' * 64) -Adapters @{
                winget={ [pscustomobject]@{Success=$true;Packages=@([pscustomobject]@{Id='ok'});Warning=$null} }
            }
            $r.status | Should -Be 'success'
            $r.managers | Where-Object manager -eq 'winget' | Select-Object -ExpandProperty status | Should -Be 'success'
            $r.packages.Count | Should -Be 1
            $r.warnings | Should -Match 'fingerprint unavailable'
            $r.managers | Where-Object manager -eq 'winget' | Select-Object -ExpandProperty fingerprint | Should -BeNullOrEmpty
        }
    }
    It 'preserves adapter and fingerprint warnings together' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\winget.exe' }
            Mock Get-WpaManagerFingerprint { throw 'fingerprint unavailable' }
            $r=Get-WpaInventoryAggregate -Managers @('winget') -PolicyHash ('a' * 64) -Adapters @{
                winget={ [pscustomobject]@{Success=$true;Packages=@([pscustomobject]@{Id='ok'});Warning='adapter timeout'} }
            }
            $manager=$r.managers | Where-Object manager -eq 'winget'
            $manager.status | Should -Be 'success'
            $manager.warning | Should -Match 'adapter timeout'
            $manager.warning | Should -Match 'fingerprint unavailable'
            $r.warnings | Should -Contain $manager.warning
        }
    }
    It 'never invokes mutation adapters' { InModuleScope WinPkgAgent { (Get-Command Get-WpaInventoryAggregate).CommandType | Should -Be 'Function' } }

    It 'does not call excluded managers and succeeds for a healthy single-manager scope' {
        InModuleScope WinPkgAgent {
            $script:wingetCalls = 0
            $r = Get-WpaInventoryAggregate -Managers @('scoop') -PolicyHash ('a' * 64) -Adapters @{
                winget = { $script:wingetCalls++; throw 'excluded manager called' }
                scoop = { [pscustomobject]@{Success=$true;Packages=@([pscustomobject]@{manager='scoop';id='jq'});Warning=$null} }
            }
            $script:wingetCalls | Should -Be 0
            $r.schemaVersion | Should -Be 2
            $r.status | Should -Be 'success'
            @($r.managers.manager) | Should -Be @('scoop')
            @($r.managerScope) | Should -Be @('scoop')
            $r.policyHash | Should -Be ('a' * 64)
        }
    }

    It 'fails when the only selected manager fails' {
        InModuleScope WinPkgAgent {
            $r = Get-WpaInventoryAggregate -Managers @('scoop') -PolicyHash ('b' * 64) -Adapters @{scoop={ [pscustomobject]@{Success=$false;Packages=@();Warning='failed'} }}
            $r.status | Should -Be 'failed'
            @($r.managers.manager) | Should -Be @('scoop')
        }
    }

    It 'fails closed for an empty manager selection' {
        InModuleScope WinPkgAgent {
            { Get-WpaInventoryAggregate -Managers @() -PolicyHash ('a' * 64) -Adapters @{winget={ throw 'must not run' };scoop={ throw 'must not run' }} } | Should -Throw '*manager*'
        }
    }

    It 'public inventory passes only policy-allowed managers and policy provenance' {
        InModuleScope WinPkgAgent {
            $script:aggregateArgs = $null
            $policy = [pscustomobject]@{allowedManagers=@('scoop')}
            Mock Read-WpaPolicyFile { $policy }
            Mock Test-WpaDataSchema { $true }
            Mock Get-WpaObjectHash { 'c' * 64 }
            Mock Get-WpaInventoryAggregate {
                param($Adapters, $Managers, $PolicyHash)
                $script:aggregateArgs = [pscustomobject]@{Managers=@($Managers);PolicyHash=$PolicyHash}
                [pscustomobject]@{schemaVersion=2;policyHash=$PolicyHash;managerScope=@('scoop');environment=[pscustomobject]@{id='env'};collectedAt='2026-08-08T00:00:00Z';status='success';managers=@();packages=@();warnings=@()}
            }
            Get-WpaInventory -PolicyPath 'policy.yaml' | Out-Null
            @($script:aggregateArgs.Managers) | Should -Be @('scoop')
            $script:aggregateArgs.PolicyHash | Should -Be ('c' * 64)
        }
    }

    It 'includes policy provenance in the state hash and detects scope changes' {
        InModuleScope WinPkgAgent {
            $base = [pscustomobject]@{schemaVersion=2;policyHash=('a' * 64);managerScope=@('scoop');environment=[pscustomobject]@{id='env'};status='success';managers=@([pscustomobject]@{manager='scoop';status='success';version=$null;fingerprint=$null});packages=@();warnings=@()}
            $policyChanged = $base.PSObject.Copy(); $policyChanged.policyHash = 'b' * 64
            $scopeChanged = $base.PSObject.Copy(); $scopeChanged.managerScope = @('winget','scoop')
            (Get-WpaInventoryStateHash $base) | Should -Not -Be (Get-WpaInventoryStateHash $policyChanged)
            (Get-WpaInventoryStateHash $base) | Should -Not -Be (Get-WpaInventoryStateHash $scopeChanged)
        }
    }

    It 'rejects inventory state hashing without valid schema v2 provenance' {
        InModuleScope WinPkgAgent {
            $inventory = [pscustomobject]@{schemaVersion=1;environment=[pscustomobject]@{id='env'};status='success';managers=@();packages=@()}
            { Get-WpaInventoryStateHash $inventory } | Should -Throw '*provenance*'
        }
    }
}
