function Get-WpaCliExitCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command,[Parameter(Mandatory)][object]$Result)
    if($Result.PSObject.Properties['valid'] -and -not $Result.valid){return 2}
    if($Command -eq 'invoke'){
        if($Result.apply.status -in @('partial-failure','failed')){return 3}
        if($Result.verify.status -in @('failed','indeterminate')){return 4}
        if($Result.verify.status -eq 'reboot-required'){return 5}
    }
    return 0
}
