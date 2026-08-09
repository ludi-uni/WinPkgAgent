function ConvertTo-WpaCliSingleQuotedLiteral {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-WpaCliPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$PolicyPath,
        [string]$WorkspacePath='./.wpa',
        [switch]$WhatIf
    )

    $workspace = [IO.Path]::GetFullPath($(if ($WorkspacePath) { $WorkspacePath } else { './.wpa' }))
    $run = New-WpaRun -ManifestPath $ManifestPath -PolicyPath $PolicyPath -WorkspacePath $workspace -WhatIf:$WhatIf
    if ($WhatIf) {
        return [pscustomobject][ordered]@{
            status='what-if'; runId=$null; runPath=$run.runPath; actionCount=0; blockedCount=0; warningCount=0; blockedReasons=@(); nextCommand=$null
        }
    }

    $runPath = Join-Path (Join-Path $workspace 'runs') $run.runId
    $planPath = Join-Path $runPath 'plan.json'
    $validation = Test-WpaPlan -PlanPath $planPath
    if (-not $validation.valid) { throw 'PREVIEW_PLAN_INVALID' }

    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 100
    $blocked = @($plan.blockedOperations)
    $status = if ($blocked.Count -gt 0) { 'blocked' } else { 'ready' }
    $nextCommand = "pwsh ./scripts/winpkg-agent.ps1 approve-run -RunPath $(ConvertTo-WpaCliSingleQuotedLiteral $runPath)"
    return [pscustomobject][ordered]@{
        status=$status
        runId=$run.runId
        runPath=$runPath
        actionCount=@($plan.actions).Count
        blockedCount=$blocked.Count
        warningCount=@($plan.warnings).Count
        blockedReasons=@($blocked | ForEach-Object {
            [pscustomobject][ordered]@{manager=$_.manager;id=$_.id;reasonCode=$_.reasonCode;reason=$_.reason}
        })
        nextCommand=$nextCommand
    }
}
