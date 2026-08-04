[CmdletBinding()]
param(
    [Parameter(Mandatory,Position=0)][ValidateSet('environment','inventory','manifest','plan','show','approve','validate-plan','invoke')][string]$Command,
    [string]$Path,[string]$ManifestPath,[string]$PolicyPath,[string]$InventoryPath,[string]$PlanPath,[string]$ApprovalPath,
    [string]$OutputPath,[string]$MarkdownPath,[string]$VerifyOutputPath,[string]$SummaryPath,[switch]$WhatIf
)
$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot '../src/WinPkgAgent/WinPkgAgent.psd1'
. (Join-Path $PSScriptRoot 'Private/ExitCode.ps1')
try {
    Import-Module $modulePath -Force
    $result=switch($Command){
        environment { Test-WpaEnvironment }
        inventory { Get-WpaInventory -OutputPath $OutputPath -WhatIf:$WhatIf }
        manifest { Test-WpaManifest -Path $Path }
        plan { New-WpaPlan -ManifestPath $ManifestPath -PolicyPath $PolicyPath -InventoryPath $InventoryPath -OutputPath $OutputPath -MarkdownPath $MarkdownPath -WhatIf:$WhatIf }
        show { Show-WpaPlan -PlanPath $PlanPath }
        approve { Approve-WpaPlan -PlanPath $PlanPath -OutputPath $OutputPath -WhatIf:$WhatIf }
        'validate-plan' { Test-WpaPlan -PlanPath $PlanPath -ApprovalPath $ApprovalPath }
        invoke { if(-not $OutputPath){$OutputPath='./artifacts/apply-result.json'};if(-not $VerifyOutputPath){$VerifyOutputPath='./artifacts/verify-result.json'};if(-not $SummaryPath){$SummaryPath='./artifacts/run-summary.md'};Invoke-WpaPlan -PlanPath $PlanPath -ApprovalPath $ApprovalPath -PolicyPath $PolicyPath -OutputPath $OutputPath -VerifyOutputPath $VerifyOutputPath -SummaryPath $SummaryPath -WhatIf:$WhatIf -Confirm:$false }
    }
    $result
    exit (Get-WpaCliExitCode -Command $Command -Result $result)
} catch {
    Write-Error ("winpkg-agent: {0}" -f $_.Exception.Message)
    exit 1
}
