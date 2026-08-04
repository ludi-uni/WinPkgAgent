[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([switch]$InstallDevelopmentDependencies)
$requirements=[ordered]@{Pester='5.6.1';PSScriptAnalyzer='1.25.0';'powershell-yaml'='0.4.12'}
$missing=@()
foreach($entry in $requirements.GetEnumerator()){
    $available=Get-Module -ListAvailable $entry.Key | Where-Object Version -GE ([version]$entry.Value) | Select-Object -First 1
    if(-not $available){$missing+="$($entry.Key)>=$($entry.Value)"}
}
if($missing.Count -eq 0){Write-Host 'All declared dependencies are available.';return}
Write-Warning ('Missing dependencies: '+($missing -join ', '))
if(-not $InstallDevelopmentDependencies){Write-Host 'No modules were installed. Review docs/dependencies.md, then rerun with -InstallDevelopmentDependencies and confirm explicitly.';return}
foreach($entry in $requirements.GetEnumerator()){
    if($PSCmdlet.ShouldProcess("$($entry.Key) $($entry.Value)",'Install CurrentUser PowerShell module')){Install-Module -Name $entry.Key -RequiredVersion $entry.Value -Scope CurrentUser -Repository PSGallery -ErrorAction Stop}
}
