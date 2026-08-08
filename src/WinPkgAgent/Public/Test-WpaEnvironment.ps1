function Test-WpaEnvironment {
    [CmdletBinding()]
    param([string]$PowerShellPath,[string]$PolicyPath)
    $configuredPath=$PowerShellPath
    $allowedManagers=@('winget','scoop')
    if($PolicyPath){
        $policy=Read-WpaPolicyFile -Path $PolicyPath
        Test-WpaDataSchema -Data $policy -SchemaName policy | Out-Null
        $allowedManagers=@($policy.allowedManagers | ForEach-Object {[string]$_})
        if(-not $configuredPath){$runtimeConfig=Get-WpaPropertyValue $policy 'runtime' $null;if($runtimeConfig){$configuredPath=[string](Get-WpaPropertyValue $runtimeConfig 'powershellPath' $null)}}
    }
    $runtime=Get-WpaPowerShellRuntimeInfo -PowerShellPath $configuredPath;$runtimeArtifact=ConvertTo-WpaPowerShellRuntimeArtifact -Runtime $runtime
    $winget=if('winget' -in $allowedManagers){[bool](Test-WpaWingetAvailable)}else{$false}
    $scoop=if('scoop' -in $allowedManagers){[bool](Test-WpaScoopAvailable)}else{$false}
    if($PolicyPath){
        $allowedManagersAvailable=$allowedManagers.Count -gt 0
        foreach($manager in $allowedManagers){
            if(($manager -eq 'winget' -and -not $winget) -or ($manager -eq 'scoop' -and -not $scoop) -or $manager -notin @('winget','scoop')){$allowedManagersAvailable=$false}
        }
    } else {
        $allowedManagersAvailable=$winget -or $scoop
    }
    [pscustomobject]@{
        schemaVersion=1; environmentId=(Get-WpaEnvironmentId); powerShellVersion=$runtimeArtifact.version
        powerShellSupported=[bool]$runtimeArtifact.compatible; powershell=$runtimeArtifact
        yamlDependencyAvailable=[bool](Get-Module -ListAvailable powershell-yaml | Where-Object Version -GE ([version]'0.4.12'))
        managers=[pscustomobject]@{winget=$winget;scoop=$scoop}; ready=([bool]$runtimeArtifact.compatible -and $allowedManagersAvailable)
    }
}
