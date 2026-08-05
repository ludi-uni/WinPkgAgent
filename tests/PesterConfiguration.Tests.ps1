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

    It 'disables TestRegistry when the runner cannot create the Pester registry key' {
        Mock Test-WpaPesterRegistryAvailable { $false }

        $configuration = Get-WpaPesterConfiguration -Path (Join-Path $root 'tests')

        $configuration.TestRegistry.Enabled.Value | Should -BeFalse
        Assert-MockCalled Test-WpaPesterRegistryAvailable -Times 1 -Exactly
    }
}
