function Test-WpaManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Alias('ManifestPath')][string]$Path)
    try {
        $manifest=Read-WpaManifestResolved -Path $Path
        Test-WpaManifestObject -Manifest $manifest | Out-Null
        Test-WpaDataSchema -Data $manifest -SchemaName manifest | Out-Null
        [pscustomobject]@{valid=$true;path=(Resolve-Path -LiteralPath $Path).Path;packageCount=@($manifest.packages).Count;errors=@()}
    } catch {
        [pscustomobject]@{valid=$false;path=$Path;packageCount=0;errors=@($_.Exception.Message)}
    }
}
