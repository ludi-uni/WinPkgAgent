function Test-WpaEnvironment {
    [CmdletBinding()]
    param([string]$PowerShellPath,[string]$PolicyPath)
    if($PolicyPath){
        $policy=Read-WpaPolicyFile -Path $PolicyPath
        Test-WpaDataSchema -Data $policy -SchemaName policy | Out-Null
        return Test-WpaEnvironmentForPolicy -Policy $policy -PowerShellPath $PowerShellPath
    }
    return Test-WpaEnvironmentForPolicy -Policy $null -PowerShellPath $PowerShellPath
}
