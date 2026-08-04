[CmdletBinding()]
param(
    [Parameter(Mandatory,Position=0)][ValidateSet('environment','inventory','manifest','plan','show','approve','validate-plan','invoke','new-run','get-run','show-run','approve-run','invoke-run','resume-verify','initialize','export-candidate')][string]$Command,
    [string]$Path,[string]$ManifestPath,[string]$PolicyPath,[string]$InventoryPath,[string]$PlanPath,[string]$ApprovalPath,[string]$RunPath,[string]$WorkspacePath,[string]$ApplyResultPath,[string]$PowerShellPath,
    [string]$OutputPath,[string]$MarkdownPath,[string]$VerifyOutputPath,[string]$SummaryPath,[switch]$WhatIf
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.4.0'){
    Write-Error @'
WinPkgAgent requires PowerShell 7.4 or newer.

Run this script with pwsh.exe, not powershell.exe.
PowerShell 7 is searched without changing PATH. You can configure runtime.powershellPath or pass -PowerShellPath to the environment command.
'@
    exit 1
}
$modulePath=Join-Path $PSScriptRoot '../src/WinPkgAgent/WinPkgAgent.psd1'
. (Join-Path $PSScriptRoot 'Private/ExitCode.ps1')
try {
    Import-Module $modulePath -Force
    $result=switch($Command){
        environment { Test-WpaEnvironment -PowerShellPath $PowerShellPath -PolicyPath $PolicyPath }
        inventory { Get-WpaInventory -OutputPath $OutputPath -WhatIf:$WhatIf }
        manifest { Test-WpaManifest -Path $Path }
        plan { New-WpaPlan -ManifestPath $ManifestPath -PolicyPath $PolicyPath -InventoryPath $InventoryPath -OutputPath $OutputPath -MarkdownPath $MarkdownPath -WhatIf:$WhatIf }
        show { Show-WpaPlan -PlanPath $PlanPath }
        approve { Approve-WpaPlan -PlanPath $PlanPath -OutputPath $OutputPath -WhatIf:$WhatIf }
        'validate-plan' { Test-WpaPlan -PlanPath $PlanPath -ApprovalPath $ApprovalPath }
        invoke { if(-not $OutputPath){$OutputPath='./artifacts/apply-result.json'};if(-not $VerifyOutputPath){$VerifyOutputPath='./artifacts/verify-result.json'};if(-not $SummaryPath){$SummaryPath='./artifacts/run-summary.md'};if($WhatIf){Invoke-WpaPlan -PlanPath $PlanPath -PolicyPath $PolicyPath -Preflight -OutputPath $OutputPath -VerifyOutputPath $VerifyOutputPath -SummaryPath $SummaryPath -Confirm:$false}else{Invoke-WpaPlan -PlanPath $PlanPath -ApprovalPath $ApprovalPath -PolicyPath $PolicyPath -OutputPath $OutputPath -VerifyOutputPath $VerifyOutputPath -SummaryPath $SummaryPath -Confirm:$false} }
        'new-run' { New-WpaRun -ManifestPath $ManifestPath -PolicyPath $PolicyPath -WorkspacePath $WorkspacePath -WhatIf:$WhatIf }
        'get-run' { Get-WpaRun -RunPath $RunPath }
        'show-run' { Show-WpaRun -RunPath $RunPath }
        'approve-run' { Approve-WpaRun -RunPath $RunPath -WhatIf:$WhatIf }
        'invoke-run' { Invoke-WpaRun -RunPath $RunPath -WhatIf:$WhatIf -DiagnosticLogging:$false }
        'resume-verify' { Resume-WpaVerification -PlanPath $PlanPath -ApplyResultPath $ApplyResultPath -VerifyOutputPath $VerifyOutputPath -WhatIf:$WhatIf }
        'initialize' { Initialize-WpaProject -Path $(if($Path){$Path}else{'.'}) -Force:$false -WhatIf:$WhatIf }
        'export-candidate' { Export-WpaManifestCandidate -InventoryPath $InventoryPath -OutputPath $OutputPath -WhatIf:$WhatIf }
    }
    $result
    exit (Get-WpaCliExitCode -Command $Command -Result $result)
} catch {
    Write-Error ("winpkg-agent: {0}" -f $_.Exception.Message)
    exit 1
}
