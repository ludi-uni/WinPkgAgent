$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'PowerShell 7 runtime resolution' {
    InModuleScope WinPkgAgent {
        It 'rejects relative and powershell.exe configured paths' {
            (Test-WpaPowerShellExecutable -Path 'pwsh.exe' -Source configured).reasonCode | Should -Be 'CONFIGURED_POWERSHELL_PATH_NOT_ABSOLUTE'
            (Test-WpaPowerShellExecutable -Path 'C:\Tools\powershell.exe' -Source configured).reasonCode | Should -Be 'CONFIGURED_POWERSHELL_INVALID'
        }

        It 'accepts PowerShell 7.4 Core and rejects older or Desktop runtimes' {
            $path=Join-Path $TestDrive 'pwsh.exe';[IO.File]::WriteAllText($path,'fixture')
            Mock Get-WpaPowerShellFileFingerprint { [pscustomobject]@{pathHash=('a'*64);fileSha256=('b'*64);fileLength=7;lastWriteTimeUtc='2026-01-01T00:00:00Z';signatureStatus='Valid';signerSubject='fixture';isReparsePoint=$false} }
            (Test-WpaPowerShellExecutable -Path $path -Source configured -ProbeJson '{"PSEdition":"Core","PSVersion":"7.4.0"}').compatible | Should -BeTrue
            (Test-WpaPowerShellExecutable -Path $path -Source configured -ProbeJson '{"PSEdition":"Core","PSVersion":"7.3.0"}').reasonCode | Should -Be 'CONFIGURED_POWERSHELL_INVALID_VERSION'
            (Test-WpaPowerShellExecutable -Path $path -Source configured -ProbeJson '{"PSEdition":"Desktop","PSVersion":"5.1.0"}').reasonCode | Should -Be 'CONFIGURED_POWERSHELL_INVALID_VERSION'
        }

        It 'uses an absolute path and fixed no-profile arguments for the runtime probe' {
            $path=Join-Path $TestDrive 'pwsh.exe';[IO.File]::WriteAllText($path,'fixture')
            Mock Get-WpaPowerShellFileFingerprint { [pscustomobject]@{pathHash=('a'*64);fileSha256=('b'*64);fileLength=7;lastWriteTimeUtc='2026-01-01T00:00:00Z';signatureStatus='Valid';signerSubject='fixture';isReparsePoint=$false} }
            Mock Invoke-WpaProcess { [pscustomobject]@{ExitCode=0;TimedOut=$false;StdOut='{"PSEdition":"Core","PSVersion":"7.4.0"}'} }
            $result=Test-WpaPowerShellExecutable -Path $path -Source configured
            $result.compatible | Should -BeTrue
            Should -Invoke Invoke-WpaProcess -ParameterFilter {$FilePath -eq [IO.Path]::GetFullPath($path) -and $Arguments -contains '-NoProfile' -and $Arguments -contains '-NonInteractive'} -Times 1 -Exactly
        }

        It 'accepts the structured PSVersion object returned by ConvertTo-Json' {
            $path=Join-Path $TestDrive 'pwsh.exe';[IO.File]::WriteAllText($path,'fixture')
            Mock Get-WpaPowerShellFileFingerprint { [pscustomobject]@{pathHash=('a'*64);fileSha256=('b'*64);fileLength=7;lastWriteTimeUtc='2026-01-01T00:00:00Z';signatureStatus='Valid';signerSubject='fixture';isReparsePoint=$false} }
            Mock Invoke-WpaProcess { [pscustomobject]@{ExitCode=0;TimedOut=$false;StdOut='{"PSEdition":"Core","PSVersion":{"Major":7,"Minor":6,"Patch":3}}'} }
            (Test-WpaPowerShellExecutable -Path $path -Source configured).compatible | Should -BeTrue
        }

        It 'does not expose the resolved path in environment output' {
            Mock Get-WpaPowerShellRuntimeInfo { [pscustomobject]@{available=$true;compatible=$true;resolvedPath='C:\Users\alice\pwsh.exe';version='7.4.0';edition='Core';source='configured';pathHash=('a'*64);fileSha256=('b'*64);fileLength=1;lastWriteTimeUtc='2026-01-01T00:00:00Z';signatureStatus='Valid';signerSubject='fixture';isReparsePoint=$false;reasonCode=$null;reason=$null} }
            Mock Test-WpaWingetAvailable {$false};Mock Test-WpaScoopAvailable {$false};Mock Get-WpaEnvironmentId {'env'}
            $json=(Test-WpaEnvironment | ConvertTo-Json -Depth 20)
            $json | Should -Not -Match 'alice|resolvedPath'
            $json | Should -Match '7\.4\.0|configured|fileSha256'
        }
    }
}
