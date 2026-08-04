Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privateRoot = Join-Path $PSScriptRoot 'Private'
$publicRoot = Join-Path $PSScriptRoot 'Public'

if (Test-Path -LiteralPath $privateRoot) {
    Get-ChildItem -LiteralPath $privateRoot -Filter '*.ps1' -File -Recurse |
        Sort-Object FullName |
        ForEach-Object { . $_.FullName }
}

# Resolve user-level manager locations before public commands and child processes run.
$null = Initialize-WpaManagerPath

if (Test-Path -LiteralPath $publicRoot) {
    Get-ChildItem -LiteralPath $publicRoot -Filter '*.ps1' -File |
        Sort-Object FullName |
        ForEach-Object { . $_.FullName }
}

Export-ModuleMember -Function @(
    'Get-WpaInventory',
    'Test-WpaEnvironment',
    'Test-WpaManifest',
    'New-WpaPlan',
    'Show-WpaPlan',
    'Approve-WpaPlan',
    'Test-WpaPlan',
    'Invoke-WpaPlan'
)
