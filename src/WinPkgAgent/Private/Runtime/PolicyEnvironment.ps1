function Test-WpaEnvironmentForPolicy {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Policy,
        [AllowNull()][string]$PowerShellPath
    )

    $configuredPath = $PowerShellPath
    $allowedManagers = if ($null -eq $Policy) { @('winget', 'scoop') } else { @($Policy.allowedManagers | ForEach-Object { [string]$_ }) }
    if ($null -ne $Policy -and -not $configuredPath) {
        $runtimeConfig = Get-WpaPropertyValue $Policy 'runtime' $null
        if ($runtimeConfig) { $configuredPath = [string](Get-WpaPropertyValue $runtimeConfig 'powershellPath' $null) }
    }

    $runtime = Get-WpaPowerShellRuntimeInfo -PowerShellPath $configuredPath
    $runtimeArtifact = ConvertTo-WpaPowerShellRuntimeArtifact -Runtime $runtime
    $winget = if ('winget' -in $allowedManagers) { [bool](Test-WpaWingetAvailable) } else { $false }
    $scoop = if ('scoop' -in $allowedManagers) { [bool](Test-WpaScoopAvailable) } else { $false }
    $allowedManagersAvailable = if ($null -eq $Policy) {
        $winget -or $scoop
    } else {
        @($allowedManagers).Count -gt 0 -and @($allowedManagers | Where-Object {
            ($_ -eq 'winget' -and -not $winget) -or ($_ -eq 'scoop' -and -not $scoop) -or $_ -notin @('winget', 'scoop')
        }).Count -eq 0
    }

    [pscustomobject]@{
        schemaVersion = 1
        environmentId = Get-WpaEnvironmentId
        powerShellVersion = $runtimeArtifact.version
        powerShellSupported = [bool]$runtimeArtifact.compatible
        powershell = $runtimeArtifact
        yamlDependencyAvailable = [bool](Get-Module -ListAvailable powershell-yaml | Where-Object Version -GE ([version]'0.4.12'))
        managers = [pscustomobject]@{ winget = $winget; scoop = $scoop }
        ready = [bool]($runtimeArtifact.compatible -and $allowedManagersAvailable)
    }
}
