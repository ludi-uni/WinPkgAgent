Describe 'shared Pester configuration' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        . (Join-Path $PSScriptRoot 'PesterConfiguration.ps1')
    }

    It 'configures the requested paths, JUnit results, and coverage' {
        $testPath = Join-Path $root 'tests'
        $resultsPath = Join-Path $root 'TestResults'

        $configuration = Get-WpaPesterConfiguration -Path $testPath -DisableRegistry

        $configuration.Run.Path.Value | Should -Be @($testPath)
        $configuration.Run.Exit.Value | Should -BeTrue
        $configuration.TestResult.Enabled.Value | Should -BeTrue
        $configuration.TestResult.OutputFormat.Value | Should -Be 'JUnitXml'
        $configuration.TestResult.OutputPath.Value | Should -Be (Join-Path $resultsPath 'pester.xml')
        $configuration.CodeCoverage.Enabled.Value | Should -BeTrue
        $configuration.CodeCoverage.Path.Value | Should -Be @((Join-Path $root 'src/WinPkgAgent/**/*.ps1'))
        $configuration.CodeCoverage.OutputPath.Value | Should -Be (Join-Path $resultsPath 'coverage.xml')
    }

    It 'explicitly disables TestRegistry when requested' {
        $configuration = Get-WpaPesterConfiguration -Path (Join-Path $root 'tests') -DisableRegistry

        $configuration.TestRegistry.Enabled.Value | Should -BeFalse
    }

    It 'enables TestRegistry after creating an absent Pester root and cleans up only the child probe' {
        $registryRoot = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Pester'
        Mock Test-Path {
            param($Path, $LiteralPath)
            if ($Path -eq $registryRoot) {
                return $false
            }

            return $true
        }
        Mock New-Item { param($Path) }
        Mock Remove-Item { param($LiteralPath) }

        $configuration = Get-WpaPesterConfiguration -Path (Join-Path $root 'tests')

        $configuration.TestRegistry.Enabled.Value | Should -BeTrue
        Assert-MockCalled New-Item -ParameterFilter { $Path -eq $registryRoot } -Times 1 -Exactly
        Assert-MockCalled New-Item -ParameterFilter { $Path -ne $registryRoot } -Times 1 -Exactly
        Assert-MockCalled Remove-Item -ParameterFilter { $LiteralPath -ne $registryRoot } -Times 1 -Exactly
        Assert-MockCalled Remove-Item -ParameterFilter { $LiteralPath -eq $registryRoot } -Times 0 -Exactly
    }

    It 'disables TestRegistry when the Pester root cannot be inspected or created' {
        Mock Test-Path { throw [UnauthorizedAccessException]::new('denied') }
        Mock New-Item { param($Path) }
        Mock Remove-Item { param($LiteralPath) }

        $configuration = Get-WpaPesterConfiguration -Path (Join-Path $root 'tests')

        $configuration.TestRegistry.Enabled.Value | Should -BeFalse
        Assert-MockCalled New-Item -Times 0 -Exactly
    }

    It 'disables TestRegistry when a child probe cannot be created' {
        $registryRoot = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Pester'
        Mock Test-Path {
            param($Path)
            return $Path -eq $registryRoot
        }
        Mock New-Item { throw [UnauthorizedAccessException]::new('denied') }
        Mock Remove-Item { param($LiteralPath) }

        $configuration = Get-WpaPesterConfiguration -Path (Join-Path $root 'tests')

        $configuration.TestRegistry.Enabled.Value | Should -BeFalse
        Assert-MockCalled New-Item -Times 1 -Exactly
        Assert-MockCalled Remove-Item -Times 0 -Exactly
    }
}
