[CmdletBinding()]
param([switch]$SkipTests)
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$parseErrors=@()
Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'scripts'),(Join-Path $root 'tests') -Recurse -Filter '*.ps1' | ForEach-Object {
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors);$parseErrors+=@($errors)
}
if($parseErrors.Count -gt 0){throw ($parseErrors.Message -join [Environment]::NewLine)}
Get-ChildItem (Join-Path $root 'schemas') -Filter '*.json' | ForEach-Object {Get-Content -Raw $_.FullName|ConvertFrom-Json|Out-Null}
Import-Module (Join-Path $root 'src/WinPkgAgent/WinPkgAgent.psd1') -Force
$sampleManifests=@((Join-Path $root 'config/packages.example.yaml'))+@(Get-ChildItem (Join-Path $root 'profiles') -Filter '*.example.yaml' -File | ForEach-Object FullName)
foreach($sample in $sampleManifests){$sampleResult=Test-WpaManifest -Path $sample;if(-not $sampleResult.valid){throw "Invalid sample manifest $sample`: $($sampleResult.errors -join '; ')"}}
$expected=@('Approve-WpaPlan','Get-WpaInventory','Invoke-WpaPlan','New-WpaPlan','Show-WpaPlan','Test-WpaEnvironment','Test-WpaManifest','Test-WpaPlan','New-WpaRun','Get-WpaRun','Show-WpaRun','Approve-WpaRun','Invoke-WpaRun','Resume-WpaVerification','Initialize-WpaProject','Export-WpaManifestCandidate')|Sort-Object
$actual=@((Get-Command -Module WinPkgAgent).Name|Sort-Object)
if(Compare-Object $expected $actual){throw 'Module manifest and exported commands differ.'}
if(-not $SkipTests){
    $pester=Get-Module -ListAvailable Pester|Where-Object Version -GE ([version]'5.6.1')|Select-Object -First 1
    if(-not $pester){throw 'Pester 5.6.1 or newer is required to run tests. Dependencies are never installed automatically.'}
    Import-Module $pester.Path;Invoke-Pester -Path (Join-Path $root 'tests')
}
Write-Host 'Build validation completed.'
