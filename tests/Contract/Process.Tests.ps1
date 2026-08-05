Describe 'Wpa process adapter contract' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }
    It 'preserves argument boundaries and exit metadata' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'fixture-manager.exe'
            [IO.File]::WriteAllText($path, 'fixture')
            $r=Invoke-WpaProcess -FilePath ([IO.Path]::GetFullPath($path)) -Arguments @('--literal','a b') -TimeoutSeconds 7 -ProcessRunner {
                param($FilePath,$Arguments,$TimeoutSeconds)
                [pscustomobject]@{ExitCode=0;StdOut='a b';StdErr='';DurationMs=2;TimedOut=$false;Started=$true}
            }
            $r.ExitCode | Should -Be 0; $r.StdOut | Should -Be 'a b'; $r.Arguments[1] | Should -Be 'a b'; $r.TimedOut | Should -BeFalse
        }
    }
    It 'reports timeout without throwing' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'fixture-manager.exe'
            [IO.File]::WriteAllText($path, 'fixture')
            $r=Invoke-WpaProcess -FilePath ([IO.Path]::GetFullPath($path)) -Arguments @('--sleep') -TimeoutSeconds 1 -ProcessRunner {
                param($FilePath,$Arguments,$TimeoutSeconds)
                $TimeoutSeconds | Should -Be 1
                [pscustomobject]@{ExitCode=$null;StdOut='';StdErr='timed out';DurationMs=1000;TimedOut=$true;Started=$true}
            }
            $r.TimedOut | Should -BeTrue
        }
    }
}
