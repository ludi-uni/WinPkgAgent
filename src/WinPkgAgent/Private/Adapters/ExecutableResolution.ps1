function Resolve-WpaManagerExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('winget','scoop')][string]$Manager
    )

    $commandName = if($Manager -eq 'winget'){'winget'}else{'scoop'}
    foreach($command in @(Get-Command -Name $commandName -All -ErrorAction SilentlyContinue)) {
        $path = if($command.Path){[string]$command.Path}elseif($command.Source){[string]$command.Source}else{$null}
        if($path){return $path}
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if($Manager -eq 'scoop' -and $env:USERPROFILE) {
        $candidates.Add((Join-Path $env:USERPROFILE 'scoop\shims\scoop.cmd'))
    }
    if($Manager -eq 'winget') {
        if($env:LOCALAPPDATA) {$candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))}
    }
    foreach($candidate in $candidates | Select-Object -Unique) {
        if(Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) {return $candidate}
    }
    return $null
}
