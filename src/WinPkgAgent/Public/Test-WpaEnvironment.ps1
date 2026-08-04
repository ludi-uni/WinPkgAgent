function Test-WpaEnvironment {
    [CmdletBinding()]
    param([string]$PowerShellPath,[string]$PolicyPath)
    $configuredPath=$PowerShellPath
    if(-not $configuredPath -and $PolicyPath){$policy=Read-WpaPolicyFile -Path $PolicyPath;$runtimeConfig=Get-WpaPropertyValue $policy 'runtime' $null;if($runtimeConfig){$configuredPath=[string](Get-WpaPropertyValue $runtimeConfig 'powershellPath' $null)}}
    $runtime=Get-WpaPowerShellRuntimeInfo -PowerShellPath $configuredPath;$runtimeArtifact=ConvertTo-WpaPowerShellRuntimeArtifact -Runtime $runtime
    $winget=Test-WpaWingetAvailable
    $scoop=Test-WpaScoopAvailable
    [pscustomobject]@{
        schemaVersion=1; environmentId=(Get-WpaEnvironmentId); powerShellVersion=$runtimeArtifact.version
        powerShellSupported=[bool]$runtimeArtifact.compatible; powershell=$runtimeArtifact
        yamlDependencyAvailable=[bool](Get-Module -ListAvailable powershell-yaml | Where-Object Version -GE ([version]'0.4.12'))
        managers=[pscustomobject]@{winget=$winget;scoop=$scoop}; ready=([bool]$runtimeArtifact.compatible -and ($winget -or $scoop))
    }
}
