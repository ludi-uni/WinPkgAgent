function Invoke-WpaManagerAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Action,[Parameter(Mandatory)][int]$TimeoutSeconds)
    Assert-WpaPackageIdentifier -Value $Action.id -Manager $Action.manager | Out-Null
    if($Action.source){Assert-WpaSourceName -Value $Action.source | Out-Null}
    switch("$($Action.manager):$($Action.operation)") {
        'winget:install' { return Install-WpaWingetPackage -Id $Action.id -Version $Action.targetVersion -Source $Action.source -TimeoutSeconds $TimeoutSeconds }
        'winget:upgrade' { return Update-WpaWingetPackage -Id $Action.id -Version $Action.targetVersion -Source $Action.source -TimeoutSeconds $TimeoutSeconds }
        'scoop:install' { return Install-WpaScoopPackage -Id $Action.id -Version $Action.targetVersion -Source $Action.source -TimeoutSeconds $TimeoutSeconds }
        'scoop:upgrade' { return Update-WpaScoopPackage -Id $Action.id -Version $Action.targetVersion -Source $Action.source -TimeoutSeconds $TimeoutSeconds }
        default { throw 'Unsupported or non-mutating plan operation.' }
    }
}

function ConvertTo-WpaRunSummaryMarkdown {
    param([Parameter(Mandatory)][object]$Result)
    $lines=@('# winpkg-agent run summary','',"- Plan: $($Result.planId)","- Status: **$($Result.status)**","- Started: $($Result.startedAt)","- Finished: $($Result.finishedAt)",'','## Operations','')
    if(@($Result.operations).Count -eq 0){$lines+='No operations were executed.'}
    foreach($operation in @($Result.operations)){$lines+="- $($operation.manager)/$($operation.id): **$($operation.status)** ($($operation.reasonCode))"}
    $lines+='';$lines+='## Recovery guidance';$lines+='';$lines+='Automatic rollback is not guaranteed. Review completed operations, reacquire inventory, and use the recorded manager diagnostics to plan manual recovery.'
    return ($lines -join [Environment]::NewLine)+[Environment]::NewLine
}
