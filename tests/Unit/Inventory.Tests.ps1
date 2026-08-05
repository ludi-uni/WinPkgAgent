Describe 'inventory aggregation' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }
    It 'preserves successful results when one manager fails' {
        InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Adapters @{winget={ [pscustomobject]@{Available=$true;Success=$true;Packages=@([pscustomobject]@{Id='a'});Warning=$null} };scoop={ [pscustomobject]@{Available=$true;Success=$false;Packages=@();Warning='bad'} }}; $r.status | Should -Be 'partial'; $r.packages.Count | Should -Be 1 }
    }
    It 'fails closed when neither manager succeeds' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Adapters @{winget={throw 'x'};scoop={throw 'y'}}; $r.status | Should -Be 'failed' } }
    It 'reports winget-only success as partial' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Adapters @{winget={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }}; $r.status | Should -Be 'partial'; $r.managers.Count | Should -Be 2 } }
    It 'reports scoop-only success as partial' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Adapters @{scoop={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }}; $r.status | Should -Be 'partial' } }
    It 'reports both successful managers as success' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Adapters @{winget={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} };scoop={ [pscustomobject]@{Success=$true;Packages=@();Warning=$null} }}; $r.status | Should -Be 'success' } }
    It 'retains timeout warning and successful packages' { InModuleScope WinPkgAgent { $r=Get-WpaInventoryAggregate -Adapters @{winget={ [pscustomobject]@{Success=$true;Packages=@([pscustomobject]@{Id='ok'});Warning=$null} };scoop={ [pscustomobject]@{Success=$false;TimedOut=$true;Packages=@();Warning='timeout'} }}; $r.status | Should -Be 'partial'; $r.packages.Count | Should -Be 1; $r.warnings | Should -Contain 'timeout' } }
    It 'preserves successful inventory when fingerprint resolution fails' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\winget.exe' }
            Mock Get-WpaManagerFingerprint { throw 'fingerprint unavailable' }
            $r=Get-WpaInventoryAggregate -Adapters @{
                winget={ [pscustomobject]@{Success=$true;Packages=@([pscustomobject]@{Id='ok'});Warning=$null} }
            }
            $r.status | Should -Be 'partial'
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
            $r=Get-WpaInventoryAggregate -Adapters @{
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
}
