function Get-WpaRunArtifactPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)][ValidateSet('run','manifest','policy','inventory','plan','planMarkdown','approval','apply','verify','journal','summary')][string]$Artifact)
    $names=@{run='run.json';manifest='manifest.yaml';policy='policy.yaml';inventory='inventory.json';plan='plan.json';planMarkdown='plan.md';approval='approval.json';apply='apply-result.json';verify='verify-result.json';journal='journal.json';summary='summary.md'}
    $runFull=[IO.Path]::GetFullPath($RunPath)
    $path=[IO.Path]::GetFullPath((Join-Path $runFull $names[$Artifact]))
    if($path -ne $runFull -and -not $path.StartsWith($runFull.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Run artifact path escapes the run directory.'}
    foreach($part in @($runFull,$path)){
        $item=Get-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Run paths may not contain reparse points.'}
    }
    return $path
}

function Read-WpaRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunPath)
    $runFile=Get-WpaRunArtifactPath -RunPath $RunPath -Artifact run
    $run=Read-WpaJsonFile $runFile
    Test-WpaDataSchema -Data $run -SchemaName run | Out-Null
    foreach($artifact in @('manifest','policy','inventory','plan','planMarkdown','approval','apply','verify','journal','summary')){
        $expected=[IO.Path]::GetFileName((Get-WpaRunArtifactPath -RunPath $RunPath -Artifact $artifact))
        $declared=[string](Get-WpaPropertyValue $run ($artifact+'Path') $expected)
        if($declared -ne $expected){throw "Run artifact path is not fixed: $artifact"}
    }
    return $run
}

function New-WpaRun {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$PolicyPath,[string]$WorkspacePath='./.wpa',[datetimeoffset]$Now=[datetimeoffset]::UtcNow)
    $workspace=[IO.Path]::GetFullPath($WorkspacePath);$runs=[IO.Path]::Combine($workspace,'runs');$stamp=$Now.ToUniversalTime().ToString('yyyyMMdd-HHmmss');$runId=($stamp+'-'+([guid]::NewGuid().ToString('N').Substring(0,8)));$runPath=[IO.Path]::Combine($runs,$runId)
    if(-not $PSCmdlet.ShouldProcess($runPath,'Create WinPkgAgent run workspace')){return [pscustomobject]@{runPath=$runPath;whatIf=$true}}
    $workspace=Resolve-WpaTrustedWorkspacePath -WorkspacePath $workspace
    $preparation=New-WpaRunPreparation -ManifestPath $ManifestPath -PolicyPath $PolicyPath -Now $Now -RunId $runId
    Publish-WpaPreparedRun -Preparation $preparation -WorkspacePath $workspace | Out-Null
    return $preparation.run
}

function Get-WpaRun { [CmdletBinding()]param([Parameter(Mandatory)][string]$RunPath) Read-WpaRun $RunPath }
function Show-WpaRun { [CmdletBinding()]param([Parameter(Mandatory)][string]$RunPath) $run=Read-WpaRun $RunPath;Show-WpaPlan -PlanPath (Get-WpaRunArtifactPath $RunPath plan);$run }
function Set-WpaRunStage { param([Parameter(Mandatory)][string]$RunPath,[Parameter(Mandatory)][ValidateSet('created','planned','preflighted','approved','applying','applied','verification-deferred','verified','failed')][string]$Stage) $run=Read-WpaRun $RunPath;$run.currentStage=$Stage;Write-WpaAtomicJson (Get-WpaRunArtifactPath $RunPath run) $run;return $run }
function Approve-WpaRun { [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$RunPath) $run=Read-WpaRun $RunPath;$approval=Approve-WpaPlan -PlanPath (Get-WpaRunArtifactPath $RunPath plan) -OutputPath (Get-WpaRunArtifactPath $RunPath approval) -WhatIf:$WhatIfPreference;if(-not $WhatIfPreference){Set-WpaRunStage -RunPath $RunPath -Stage approved|Out-Null};$approval }
function Invoke-WpaRun { [CmdletBinding()]param([Parameter(Mandatory)][string]$RunPath,[switch]$WhatIf,[switch]$DiagnosticLogging)
    $run=Read-WpaRun $RunPath;$planPath=Get-WpaRunArtifactPath $RunPath plan;$policyPath=Get-WpaRunArtifactPath $RunPath policy
    if($WhatIf){$result=Invoke-WpaPlan -PlanPath $planPath -PolicyPath $policyPath -Preflight -WhatIf:$false;Set-WpaRunStage -RunPath $RunPath -Stage preflighted|Out-Null}
    else{$result=Invoke-WpaPlan -PlanPath $planPath -ApprovalPath (Get-WpaRunArtifactPath $RunPath approval) -PolicyPath $policyPath -OutputPath (Get-WpaRunArtifactPath $RunPath apply) -VerifyOutputPath (Get-WpaRunArtifactPath $RunPath verify) -SummaryPath (Get-WpaRunArtifactPath $RunPath summary) -DiagnosticLogging:$DiagnosticLogging;$stage=if($result.verify.status -eq 'reboot-required'){'verification-deferred'}elseif($result.verify.status -eq 'success'){'verified'}elseif($result.apply.status -eq 'failed' -or $result.apply.status -eq 'partial-failure'){'failed'}else{'applied'};Set-WpaRunStage -RunPath $RunPath -Stage $stage|Out-Null};$result
}
