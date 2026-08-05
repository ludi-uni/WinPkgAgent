function Test-WpaPesterRegistryAvailable {
    [CmdletBinding()]
    param()

    $registryRoot = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Pester'
    $probePath = Join-Path $registryRoot ("WinPkgAgent-$([guid]::NewGuid().ToString('N'))")
    $probeCreated = $false

    try {
        if (-not (Test-Path -Path $registryRoot -PathType Container -ErrorAction Stop)) {
            New-Item -Path $registryRoot -ErrorAction Stop | Out-Null
        }
        New-Item -Path $probePath -ErrorAction Stop | Out-Null
        $probeCreated = $true
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($probeCreated) {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-WpaPesterConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path,

        [switch]$DisableRegistry
    )

    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $resultsPath = Join-Path $repositoryRoot 'TestResults'
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $Path
    $configuration.Run.Exit = $true
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = Join-Path $resultsPath 'pester.xml'
    $configuration.TestResult.OutputFormat = 'JUnitXml'
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = Join-Path $repositoryRoot 'src/WinPkgAgent/**/*.ps1'
    $configuration.CodeCoverage.OutputPath = Join-Path $resultsPath 'coverage.xml'
    $configuration.TestRegistry.Enabled = -not ($DisableRegistry -or -not (Test-WpaPesterRegistryAvailable))

    return $configuration
}
