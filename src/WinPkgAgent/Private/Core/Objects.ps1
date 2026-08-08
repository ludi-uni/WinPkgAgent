function Get-WpaPropertyValue {
    [CmdletBinding()]
    param([AllowNull()][object]$InputObject, [Parameter(Mandatory)][string]$Name, [AllowNull()][object]$Default = $null)
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-WpaLogicalPackageName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $name = $Id.ToLowerInvariant() -replace '[^a-z0-9._-]+','-'
    $name = $name.Trim('-')
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'package' }
    if ($name -notmatch '^[a-z0-9]') { $name = 'package-' + $name }
    if ($name.Length -gt 64) { $name = $name.Substring(0,64).TrimEnd('-') }
    return $name
}
