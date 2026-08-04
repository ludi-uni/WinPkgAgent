function Test-WpaEnvironment {
    [CmdletBinding()]
    param()
    $winget=Test-WpaWingetAvailable
    $scoop=Test-WpaScoopAvailable
    [pscustomobject]@{
        schemaVersion=1; environmentId=(Get-WpaEnvironmentId); powerShellVersion=$PSVersionTable.PSVersion.ToString()
        powerShellSupported=($PSVersionTable.PSVersion -ge [version]'7.4'); yamlDependencyAvailable=[bool](Get-Module -ListAvailable powershell-yaml | Where-Object Version -GE ([version]'0.4.12'))
        managers=[pscustomobject]@{winget=$winget;scoop=$scoop}; ready=($PSVersionTable.PSVersion -ge [version]'7.4' -and ($winget -or $scoop))
    }
}
