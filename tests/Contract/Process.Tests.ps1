Describe 'Wpa process adapter contract' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }
    It 'preserves argument boundaries and exit metadata' {
        InModuleScope WinPkgAgent { $r=Invoke-WpaProcess -FilePath 'pwsh' -Arguments @('-NoProfile','-Command','[Console]::Write("a b")'); $r.ExitCode | Should -Be 0; $r.StdOut | Should -Be 'a b'; $r.Arguments[2] | Should -Be '[Console]::Write("a b")'; $r.TimedOut | Should -BeFalse }
    }
    It 'reports timeout without throwing' {
        InModuleScope WinPkgAgent { $r=Invoke-WpaProcess -FilePath 'pwsh' -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 3') -TimeoutSeconds 1; $r.TimedOut | Should -BeTrue }
    }
}
