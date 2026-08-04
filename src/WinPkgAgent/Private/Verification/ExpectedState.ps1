function Test-WpaExpectedState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Action,[Parameter(Mandatory)][object]$Inventory)
    $package=@($Inventory.packages | Where-Object {$_.manager -eq $Action.manager -and $_.id -eq $Action.id}) | Select-Object -First 1
    if($null -eq $package){return [pscustomobject]@{name=$Action.name;manager=$Action.manager;id=$Action.id;status='indeterminate';reasonCode='MANAGER_PACKAGE_NOT_FOUND'}}
    if($Action.targetVersion -and $package.installedVersion -ne $Action.targetVersion){return [pscustomobject]@{name=$Action.name;manager=$Action.manager;id=$Action.id;status='verification-failed';reasonCode='VERSION_MISMATCH';actualVersion=$package.installedVersion}}
    $verification=Get-WpaPropertyValue $Action 'verification'
    if($verification){
        $command=Get-Command $verification.command -CommandType Application -ErrorAction SilentlyContinue
        if(-not $command){return [pscustomobject]@{name=$Action.name;manager=$Action.manager;id=$Action.id;status='verification-failed';reasonCode='COMMAND_NOT_ON_PATH'}}
        $result=Invoke-WpaProcess -FilePath $command.Source -Arguments @($verification.arguments) -TimeoutSeconds 30
        if($result.ExitCode -ne 0 -or $result.TimedOut){return [pscustomobject]@{name=$Action.name;manager=$Action.manager;id=$Action.id;status='verification-failed';reasonCode='COMMAND_VERIFICATION_FAILED'}}
    }
    [pscustomobject]@{name=$Action.name;manager=$Action.manager;id=$Action.id;status='verified';reasonCode='EXPECTED_STATE_PRESENT';actualVersion=$package.installedVersion}
}
