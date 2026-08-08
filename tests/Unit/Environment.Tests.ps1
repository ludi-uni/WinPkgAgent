$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'policy-aware environment readiness' {
    InModuleScope WinPkgAgent {
        BeforeEach {
            Mock Get-WpaEnvironmentId { 'fixture-environment' }
            Mock Get-Module { [pscustomobject]@{ Name = 'powershell-yaml'; Version = [version]'0.4.12' } }
            Mock Get-WpaPowerShellRuntimeInfo {
                [pscustomobject]@{ available = $true; compatible = $true; version = '7.4.0'; edition = 'Core'; source = 'fixture'; pathHash = 'a' * 64; fileSha256 = 'b' * 64; fileLength = 1; lastWriteTimeUtc = '2026-01-01T00:00:00Z'; signatureStatus = 'Valid'; signerSubject = 'fixture'; isReparsePoint = $false; reasonCode = $null; reason = $null; checkedCandidates = @() }
            }
            Mock ConvertTo-WpaPowerShellRuntimeArtifact { $Runtime }
            Mock Test-WpaDataSchema { $true }
        }

        It 'does not probe excluded WinGet for a ready Scoop-only policy' {
            $policy = [pscustomobject]@{ schemaVersion = 1; allowedManagers = @('scoop'); runtime = [pscustomobject]@{ powershellPath = 'C:\fixture\pwsh.exe' } }
            Mock Read-WpaPolicyFile { $policy }
            Mock Test-WpaScoopAvailable { $true }
            Mock Test-WpaWingetAvailable { throw 'excluded WinGet manager was probed' }

            $result = Test-WpaEnvironment -PolicyPath 'codex-policy.yaml'

            $result.ready | Should -BeTrue
            $result.managers.scoop | Should -BeTrue
            $result.managers.winget | Should -BeFalse
            Should -Invoke Test-WpaScoopAvailable -Times 1 -Exactly
            Should -Invoke Test-WpaWingetAvailable -Times 0 -Exactly
            Should -Invoke Get-WpaPowerShellRuntimeInfo -ParameterFilter { $PowerShellPath -eq 'C:\fixture\pwsh.exe' } -Times 1 -Exactly
        }

        It 'is not ready when an allowed desktop manager is unavailable' {
            $policy = [pscustomobject]@{ schemaVersion = 1; allowedManagers = @('winget', 'scoop') }
            Mock Read-WpaPolicyFile { $policy }
            Mock Test-WpaWingetAvailable { $false }
            Mock Test-WpaScoopAvailable { $true }

            $result = Test-WpaEnvironment -PolicyPath 'desktop-policy.yaml'

            $result.ready | Should -BeFalse
            $result.managers.winget | Should -BeFalse
            $result.managers.scoop | Should -BeTrue
            Should -Invoke Test-WpaWingetAvailable -Times 1 -Exactly
            Should -Invoke Test-WpaScoopAvailable -Times 1 -Exactly
        }

        It 'fails closed when the supplied policy does not validate' {
            $policy = [pscustomobject]@{ schemaVersion = 1; allowedManagers = @('scoop') }
            Mock Read-WpaPolicyFile { $policy }
            Mock Test-WpaDataSchema { throw 'invalid policy fixture' }
            Mock Test-WpaScoopAvailable { throw 'manager probe must not run' }

            { Test-WpaEnvironment -PolicyPath 'invalid-policy.yaml' } | Should -Throw '*invalid policy fixture*'
            Should -Invoke Test-WpaScoopAvailable -Times 0 -Exactly
        }

        It 'is not ready when the selected PowerShell runtime is incompatible' {
            $policy = [pscustomobject]@{ schemaVersion = 1; allowedManagers = @('scoop') }
            Mock Read-WpaPolicyFile { $policy }
            Mock Get-WpaPowerShellRuntimeInfo { [pscustomobject]@{ available = $true; compatible = $false; version = '7.3.0'; edition = 'Core'; source = 'fixture'; pathHash = $null; fileSha256 = $null; fileLength = $null; lastWriteTimeUtc = $null; signatureStatus = $null; signerSubject = $null; isReparsePoint = $false; reasonCode = 'CONFIGURED_POWERSHELL_INVALID_VERSION'; reason = 'fixture runtime is too old'; checkedCandidates = @() } }
            Mock Test-WpaScoopAvailable { $true }

            $result = Test-WpaEnvironment -PolicyPath 'runtime-policy.yaml'

            $result.ready | Should -BeFalse
            $result.powerShellSupported | Should -BeFalse
            $result.managers.scoop | Should -BeTrue
        }
    }
}
