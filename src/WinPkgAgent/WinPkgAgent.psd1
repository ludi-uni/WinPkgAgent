@{
    RootModule = 'WinPkgAgent.psm1'
    ModuleVersion = '0.1.0'
    GUID = '46da7775-c981-48ca-b3c2-b1564cbb2c5a'
    Author = 'winpkg-agent contributors'
    CompanyName = 'Community'
    Copyright = '(c) winpkg-agent contributors. MIT License.'
    Description = 'Fail-closed orchestration for declared WinGet and Scoop package state.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
        'Get-WpaInventory',
        'Test-WpaEnvironment',
        'Test-WpaManifest',
        'New-WpaPlan',
        'Show-WpaPlan',
        'Approve-WpaPlan',
        'Test-WpaPlan',
        'Invoke-WpaPlan','New-WpaRun','Get-WpaRun','Show-WpaRun','Approve-WpaRun','Invoke-WpaRun','Resume-WpaVerification','Initialize-WpaProject','Export-WpaManifestCandidate'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'WinGet', 'Scoop', 'PackageManagement', 'Safety')
            LicenseUri = 'https://opensource.org/license/mit'
            Prerelease = 'preview'
            ExternalModuleDependencies = @('powershell-yaml')
        }
    }
}
