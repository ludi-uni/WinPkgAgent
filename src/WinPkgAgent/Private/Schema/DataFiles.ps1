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
    return [IO.File]::ReadAllText($resolved, [Text.UTF8Encoding]::new($false, $true))
}

function Read-WpaJsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $text = Read-WpaTextFile -Path $Path
    try { return $text | ConvertFrom-Json -Depth 100 } catch { throw "Invalid JSON file: $($_.Exception.Message)" }
}

function Read-WpaYamlFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $yamlModule = Get-Module -ListAvailable -Name powershell-yaml | Where-Object Version -GE ([version]'0.4.12') | Select-Object -First 1
    if (-not $yamlModule) { throw 'powershell-yaml 0.4.12 or newer is required. Install it explicitly after reviewing the dependency documentation.' }
    Import-Module $yamlModule.Path -ErrorAction Stop
    $text = Read-WpaTextFile -Path $Path
    try { return ConvertFrom-Yaml -Yaml $text -Ordered } catch { throw "Invalid YAML file: $($_.Exception.Message)" }
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
