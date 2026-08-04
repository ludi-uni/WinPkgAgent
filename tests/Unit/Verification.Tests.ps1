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
    }
}
