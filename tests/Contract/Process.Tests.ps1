Describe 'Wpa process adapter contract' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }

    BeforeEach { $global:pwshPath = (Get-Command pwsh).Source }
    It 'preserves argument boundaries and exit metadata' {
        InModuleScope WinPkgAgent { param($path)
            $r=Invoke-WpaProcess -FilePath $path -Arguments @('-NoProfile','-Command','[Console]::Write("a b")')
            $r.ExitCode | Should -Be 0
            $r.StdOut | Should -Be 'a b'
            $r.Arguments[2] | Should -Be '[Console]::Write("a b")'
            $r.TimedOut | Should -BeFalse
        } $global:pwshPath
    }
    It 'reports timeout without throwing' {
        InModuleScope WinPkgAgent { param($path)
            $r=Invoke-WpaProcess -FilePath $path -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 3') -TimeoutSeconds 1
            $r.TimedOut | Should -BeTrue
        } $global:pwshPath
    }
    It 'throws on relative FilePath' {
        InModuleScope WinPkgAgent { { Invoke-WpaProcess -FilePath '.\\pwsh' } | Should -Throw }
    }
}
