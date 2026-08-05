function ConvertTo-WpaCanonicalValue {
    [CmdletBinding()]
    param([AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string]) {
        if($InputObject -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$'){
            $parsed=[datetimeoffset]::MinValue
            if([datetimeoffset]::TryParse($InputObject,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)){return $parsed.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ',[Globalization.CultureInfo]::InvariantCulture)}
        }
        return $InputObject
    }
    if ($InputObject -is [char] -or $InputObject -is [bool] -or $InputObject -is [byte] -or $InputObject -is [sbyte] -or $InputObject -is [int16] -or
        $InputObject -is [uint16] -or $InputObject -is [int32] -or $InputObject -is [uint32] -or
        $InputObject -is [int64] -or $InputObject -is [uint64] -or $InputObject -is [decimal] -or
        $InputObject -is [double] -or $InputObject -is [single]) { return $InputObject }

    if ($InputObject -is [datetime]) { return $InputObject.ToUniversalTime().ToString('o') }
    if ($InputObject -is [datetimeoffset]) { return $InputObject.ToUniversalTime().ToString('o') }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($InputObject.Keys | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)) {
            $ordered[$key] = ConvertTo-WpaCanonicalValue -InputObject $InputObject[$key]
        }
        return $ordered
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $items=[object[]]@($InputObject | ForEach-Object { ConvertTo-WpaCanonicalValue -InputObject $_ })
        return ,$items
    }

    $properties = @($InputObject.PSObject.Properties | Where-Object MemberType -in @('NoteProperty','Property'))
    if ($properties.Count -gt 0) {
        $ordered = [ordered]@{}
        foreach ($property in @($properties | Sort-Object Name -CaseSensitive)) {
            $ordered[$property.Name] = ConvertTo-WpaCanonicalValue -InputObject $property.Value
        }
        return $ordered
    }

    return [string]$InputObject
}

function ConvertTo-WpaCanonicalJson {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][object]$InputObject)
    process {
        ConvertTo-WpaCanonicalValue -InputObject $InputObject | ConvertTo-Json -Depth 100 -Compress
    }
}

function Get-WpaSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-WpaObjectHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$InputObject)
    return Get-WpaSha256 -Text (ConvertTo-WpaCanonicalJson -InputObject $InputObject)
}

function Get-WpaInventoryStateHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Inventory)

    $environment = Get-WpaPropertyValue $Inventory 'environment'
    $environmentId = Get-WpaPropertyValue $environment 'id'
    if([string]::IsNullOrWhiteSpace([string]$environmentId)){throw 'INVENTORY_ENVIRONMENT_UNAVAILABLE: inventory environment identity is missing.'}
    $managers = @(Get-WpaPropertyValue $Inventory 'managers' @() | ForEach-Object {
        [ordered]@{ manager = $_.manager; status = $_.status; version = $_.version; fingerprint = (Get-WpaPropertyValue $_ 'fingerprint') }
    } | Sort-Object manager)
    $packages = @(Get-WpaPropertyValue $Inventory 'packages' @() | ForEach-Object {
        [ordered]@{
            manager = (Get-WpaPropertyValue $_ 'manager'); id = (Get-WpaPropertyValue $_ 'id'); displayName = (Get-WpaPropertyValue $_ 'displayName')
            installedVersion = (Get-WpaPropertyValue $_ 'installedVersion' (Get-WpaPropertyValue $_ 'Version')); availableVersion = (Get-WpaPropertyValue $_ 'availableVersion')
            source = (Get-WpaPropertyValue $_ 'source'); scope = (Get-WpaPropertyValue $_ 'scope')
        }
    } | Sort-Object manager,id)
    $state = [ordered]@{
        environmentId = $environmentId
        status = (Get-WpaPropertyValue $Inventory 'status' 'success')
        managers = $managers
        packages = $packages
    }
    return Get-WpaObjectHash -InputObject $state
}

function ConvertTo-WpaInventoryBoundary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Inventory)

    $environment = Get-WpaPropertyValue $Inventory 'environment'
    $environmentId = Get-WpaPropertyValue $environment 'id'
    if([string]::IsNullOrWhiteSpace([string]$environmentId)){throw 'INVENTORY_ENVIRONMENT_UNAVAILABLE: inventory environment identity is missing.'}

    $normalized=[ordered]@{}
    foreach($property in @($Inventory.PSObject.Properties | Where-Object MemberType -in @('NoteProperty','Property'))){$normalized[$property.Name]=$property.Value}
    $normalized['environment']=[pscustomobject]@{id=$environmentId}
    $normalized['managers']=@((Get-WpaPropertyValue $Inventory 'managers' @()))
    $normalized['packages']=@((Get-WpaPropertyValue $Inventory 'packages' @()))
    $normalized['warnings']=@((Get-WpaPropertyValue $Inventory 'warnings' @()))
    return [pscustomobject]$normalized
}
