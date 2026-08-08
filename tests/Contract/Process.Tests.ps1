Describe 'Wpa process adapter contract' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }
    It 'uses a StrictMode-safe production default when no fixture factory is configured' {
        InModuleScope WinPkgAgent {
            $script:WpaProcessFactory | Should -BeNullOrEmpty
        }
    }

    It 'preserves argument boundaries and exit metadata' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'fixture-manager.exe'
            [IO.File]::WriteAllText($path, 'fixture')
            $script:WpaProcessFactory = {
                param($StartInfo)
                [void]($script:WpaCapturedStartInfo = $StartInfo)
                $output = [pscustomobject]@{}
                Add-Member -InputObject $output -MemberType ScriptMethod -Name ReadToEndAsync -Value { [Threading.Tasks.Task]::FromResult('a b') } | Out-Null
                $error = [pscustomobject]@{}
                Add-Member -InputObject $error -MemberType ScriptMethod -Name ReadToEndAsync -Value { [Threading.Tasks.Task]::FromResult('') } | Out-Null
                $fake = [pscustomobject]@{ StartInfo=$StartInfo;StandardOutput=$output;StandardError=$error;ExitCode=0 }
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Start -Value { $true } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) if($PSBoundParameters.ContainsKey('Milliseconds')){$true} } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Kill -Value { param($EntireProcess) } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value { } | Out-Null
                $fake
            }
            try { $r=Invoke-WpaProcess -FilePath ([IO.Path]::GetFullPath($path)) -Arguments @('--literal','a b') -TimeoutSeconds 7 }
            finally { $script:WpaProcessFactory = $null }
            $r.ExitCode | Should -Be 0; $r.StdOut | Should -Be 'a b'; $r.Arguments[1] | Should -Be 'a b'; $r.TimedOut | Should -BeFalse
            @($script:WpaCapturedStartInfo.ArgumentList) | Should -Be @('--literal','a b')
            $script:WpaCapturedStartInfo = $null
        }
    }
    It 'enforces timeout and bounds metadata through the adapter-owned process lifecycle' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'fixture-manager.exe'
            [IO.File]::WriteAllText($path, 'fixture')
            $script:WpaProcessFactory = {
                param($StartInfo)
                $output = [pscustomobject]@{}
                Add-Member -InputObject $output -MemberType ScriptMethod -Name ReadToEndAsync -Value { [Threading.Tasks.Task]::FromResult('') } | Out-Null
                $error = [pscustomobject]@{}
                Add-Member -InputObject $error -MemberType ScriptMethod -Name ReadToEndAsync -Value { [Threading.Tasks.Task]::FromResult(('x' * 5000)) } | Out-Null
                $fake = [pscustomobject]@{ StartInfo=$StartInfo;StandardOutput=$output;StandardError=$error;ExitCode=99 }
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Start -Value { $true } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) if($Milliseconds -le 1000){$false}else{$true} } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Kill -Value { param($EntireProcess) } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value { } | Out-Null
                $fake
            }
            try {
                $timer = [Diagnostics.Stopwatch]::StartNew()
                $r=Invoke-WpaProcess -FilePath ([IO.Path]::GetFullPath($path)) -Arguments @('--sleep','a b') -TimeoutSeconds 1
                $timer.Stop()
            } finally { $script:WpaProcessFactory = $null }
            $timer.ElapsedMilliseconds | Should -BeLessThan 1000
            $r.TimedOut | Should -BeTrue
            $r.ExitCode | Should -BeNullOrEmpty
            $r.DurationMs | Should -BeGreaterOrEqual 0
            $r.DurationMs | Should -BeLessThan 6000
            $r.StdErr.Length | Should -BeLessOrEqual 4096
            $r.Arguments[1] | Should -Be 'a b'
        }
    }
    It 'preserves redacted but non-truncated output for bounded table parsers' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'fixture-manager.exe'
            [IO.File]::WriteAllText($path, 'fixture')
            $script:WpaProcessFactory = {
                param($StartInfo)
                $output = [pscustomobject]@{}
                Add-Member -InputObject $output -MemberType ScriptMethod -Name ReadToEndAsync -Value { [Threading.Tasks.Task]::FromResult(('row' * 5000)) } | Out-Null
                $error = [pscustomobject]@{}
                Add-Member -InputObject $error -MemberType ScriptMethod -Name ReadToEndAsync -Value { [Threading.Tasks.Task]::FromResult('') } | Out-Null
                $fake = [pscustomobject]@{ StartInfo=$StartInfo;StandardOutput=$output;StandardError=$error;ExitCode=0 }
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Start -Value { $true } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) if($PSBoundParameters.ContainsKey('Milliseconds')){$true} } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Kill -Value { param($EntireProcess) } | Out-Null
                Add-Member -InputObject $fake -MemberType ScriptMethod -Name Dispose -Value { } | Out-Null
                $fake
            }
            try { $r=Invoke-WpaProcess -FilePath ([IO.Path]::GetFullPath($path)) -NoTruncateOutput }
            finally { $script:WpaProcessFactory = $null }
            $r.StdOut.Length | Should -Be 15000
        }
    }
}
