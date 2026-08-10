function Read-WpaTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 10485760)][int]$MaxBytes = 5242880
    )
    if($Path -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Parent traversal segments are not accepted.'}
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $item = Get-Item -LiteralPath $resolved -Force
    if ($item.PSIsContainer -or $item.Length -gt $MaxBytes) { throw 'Input file is not a regular file within the size limit.' }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse-point input files are not accepted.' }
    $cursor=Split-Path $resolved -Parent
    while($cursor){$ancestor=Get-Item -LiteralPath $cursor -Force;if(($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Inputs beneath reparse-point directories are not accepted.'};$next=Split-Path $cursor -Parent;if($next -eq $cursor){break};$cursor=$next}
    $bytes = [IO.File]::ReadAllBytes($resolved)
    if ($bytes.Length -gt $MaxBytes) { throw 'Input file is not a regular file within the size limit.' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'INPUT_UTF8_INVALID' }
    try {
        return [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    } catch [Text.DecoderFallbackException] {
        throw 'INPUT_UTF8_INVALID'
    }
}

function Read-WpaJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $text = Read-WpaTextFile -Path $Path
    try { return $text | ConvertFrom-Json -Depth 100 } catch { throw "Invalid JSON file: $($_.Exception.Message)" }
}

function ConvertFrom-WpaYamlText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $yamlModule = Get-Module -ListAvailable -Name powershell-yaml | Where-Object Version -GE ([version]'0.4.12') | Select-Object -First 1
    if (-not $yamlModule) { throw 'powershell-yaml 0.4.12 or newer is required. Install it explicitly after reviewing the dependency documentation.' }
    Import-Module $yamlModule.Path -ErrorAction Stop
    try { return ConvertFrom-Yaml -Yaml $Text -Ordered } catch { throw "Invalid YAML file: $($_.Exception.Message)" }
}

function Read-WpaYamlFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    return ConvertFrom-WpaYamlText -Text (Read-WpaTextFile -Path $Path)
}

function Test-WpaIso8601Timestamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$FieldName
    )
    $match = [regex]::Match($Value, '^(?<year>[0-9]{4})-(?<month>[0-9]{2})-(?<day>[0-9]{2})T(?<hour>[0-9]{2}):(?<minute>[0-9]{2}):(?<second>[0-9]{2})(?:\.[0-9]+)?(?<zone>Z|[+-](?<offsetHour>[0-9]{2}):(?<offsetMinute>[0-9]{2}))$')
    if (-not $match.Success) { throw "Invalid ISO 8601 timestamp in $FieldName." }
    try {
        [datetime]::new(
            [int]$match.Groups['year'].Value,
            [int]$match.Groups['month'].Value,
            [int]$match.Groups['day'].Value,
            [int]$match.Groups['hour'].Value,
            [int]$match.Groups['minute'].Value,
            [int]$match.Groups['second'].Value,
            [DateTimeKind]::Unspecified
        ) | Out-Null
    } catch {
        throw "Invalid ISO 8601 timestamp in $FieldName."
    }
    if ($match.Groups['zone'].Value -ne 'Z' -and ([int]$match.Groups['offsetHour'].Value -gt 23 -or [int]$match.Groups['offsetMinute'].Value -gt 59)) {
        throw "Invalid ISO 8601 timestamp offset in $FieldName."
    }
}

function Test-WpaJsonTimestampElement {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Text.Json.JsonElement]$Element)
    switch ($Element.ValueKind) {
        Object {
            foreach ($property in $Element.EnumerateObject()) {
                if ($property.Name -in @('approvedAt', 'collectedAt', 'createdAt', 'expiresAt', 'finishedAt', 'lastWriteTimeUtc', 'startedAt', 'updatedAt', 'verifiedAt')) {
                    if ($property.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
                        Test-WpaIso8601Timestamp -Value $property.Value.GetString() -FieldName $property.Name
                    }
                } else {
                    Test-WpaJsonTimestampElement -Element $property.Value
                }
            }
        }
        Array {
            foreach ($item in $Element.EnumerateArray()) { Test-WpaJsonTimestampElement -Element $item }
        }
    }
}

function Test-WpaSchemaTimestamp {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)
    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try { Test-WpaJsonTimestampElement -Element $document.RootElement } finally { $document.Dispose() }
}

function Test-WpaDataSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Data,
        [Parameter(Mandatory)][string]$SchemaName
    )
    $schemaPath = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent) "schemas/$SchemaName.schema.json"
    if (-not (Test-Path -LiteralPath $schemaPath)) { throw "Schema not found: $SchemaName" }
    $json = $Data | ConvertTo-Json -Depth 100
    $errors = $null
    if (-not (Test-Json -Json $json -SchemaFile $schemaPath -ErrorVariable errors)) {
        throw "Data does not match $SchemaName schema: $($errors -join '; ')"
    }
    Test-WpaSchemaTimestamp -Json $json
    return $true
}

function Read-WpaManifestResolved {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $manifest = Read-WpaYamlFile -Path $Path
    $allPackages = [System.Collections.Generic.List[object]]::new()
    $manifestDirectory = Split-Path (Resolve-Path -LiteralPath $Path).Path -Parent
    $profileNames=@(Get-WpaPropertyValue $manifest 'profiles' @())
    foreach ($profileName in $profileNames) {
        if ($profileName -notmatch '^[a-z0-9][a-z0-9-]{0,31}$') { throw 'Invalid profile name.' }
        $candidates = @(
            [IO.Path]::GetFullPath((Join-Path $manifestDirectory "profiles/$profileName.yaml")),
            [IO.Path]::GetFullPath((Join-Path $manifestDirectory "../profiles/$profileName.yaml")),
            [IO.Path]::GetFullPath((Join-Path $manifestDirectory "../profiles/$profileName.example.yaml"))
        )
        $profilePath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $profilePath) { throw "Profile not found: $profileName" }
        $profileData = Read-WpaYamlFile -Path $profilePath
        if (@(Get-WpaPropertyValue $profileData 'profiles' @()).Count -gt 0) { throw 'Nested profiles are not supported.' }
        foreach ($package in @($profileData.packages)) { $allPackages.Add($package) }
    }
    foreach ($package in @($manifest.packages)) { $allPackages.Add($package) }
    return [pscustomobject]@{ schemaVersion = $manifest.schemaVersion; profiles = @($profileNames); packages = @($allPackages) }
}

function Read-WpaPolicyFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $policy = Read-WpaYamlFile -Path $Path
    Test-WpaPolicyObject -Policy $policy | Out-Null
    return $policy
}
