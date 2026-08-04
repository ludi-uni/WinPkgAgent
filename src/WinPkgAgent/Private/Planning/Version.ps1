function Compare-WpaVersionChange {
    [CmdletBinding()]
    param([AllowNull()][string]$InstalledVersion, [AllowNull()][string]$AvailableVersion)
    if ([string]::IsNullOrWhiteSpace($InstalledVersion) -or [string]::IsNullOrWhiteSpace($AvailableVersion)) { return 'unknown' }
    if ($InstalledVersion -eq $AvailableVersion) { return 'none' }
    $pattern = '^[vV]?(?<major>\d+)\.(?<minor>\d+)(?:\.(?<patch>\d+))?(?:[-+].*)?$'
    $old = [regex]::Match($InstalledVersion, $pattern)
    $new = [regex]::Match($AvailableVersion, $pattern)
    if (-not $old.Success -or -not $new.Success) { return 'unknown' }
    $oldParts = @([int64]$old.Groups['major'].Value, [int64]$old.Groups['minor'].Value, $(if ($old.Groups['patch'].Success) { [int64]$old.Groups['patch'].Value } else { 0 }))
    $newParts = @([int64]$new.Groups['major'].Value, [int64]$new.Groups['minor'].Value, $(if ($new.Groups['patch'].Success) { [int64]$new.Groups['patch'].Value } else { 0 }))
    if ($newParts[0] -ne $oldParts[0]) { return 'major' }
    if ($newParts[1] -ne $oldParts[1]) { return 'minor' }
    if ($newParts[2] -ne $oldParts[2]) { return 'patch' }
    return 'unknown'
}
