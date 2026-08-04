function Initialize-WpaProject {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path='.',[switch]$Force)
    $root=[IO.Path]::GetFullPath($Path);$files=@{'packages.yaml'=(Get-Content (Join-Path $PSScriptRoot '../../../config/packages.example.yaml') -Raw);'policy.yaml'=(Get-Content (Join-Path $PSScriptRoot '../../../config/policy.default.yaml') -Raw);'.gitignore'="artifacts/`n.wpa/`n";'README.local.md'='# Local WinPkgAgent project`n`nRun `Test-WpaEnvironment` before planning. No packages are installed by initialization.'}
    [IO.Directory]::CreateDirectory($root)|Out-Null
    foreach($name in $files.Keys){$target=Join-Path $root $name;if((Test-Path -LiteralPath $target) -and -not $Force){throw "Refusing to overwrite existing file: $name"};if($PSCmdlet.ShouldProcess($target,'Create project file')){Write-WpaAtomicText $target $files[$name]}}
    [pscustomobject]@{path=$root;created=@($files.Keys)}
}
