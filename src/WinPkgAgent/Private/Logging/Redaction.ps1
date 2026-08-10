function Protect-WpaSensitiveText {
    [CmdletBinding()]
    param([AllowNull()][string]$Text,[switch]$NoTruncate)
    if ($null -eq $Text) { return $null }
    # Remove terminal control sequences before persisting any diagnostic text.
    $result = $Text -replace "`e\[[0-?]*[ -/]*[@-~]", ''
    $result = $result -replace "`e\][^`a]*(?:`a|`e\\)", ''
    $result = $result -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
    $result = $result -replace '(?i)(authorization\s*:\s*bearer\s+)\S+', '$1[REDACTED]'
    $result = $result -replace '(?i)\b(token|bearer|password|secret|api[_-]?key|credential)\s*[=:]\s*[^\s,;]+', '$1=[REDACTED]'
    $result = $result -replace '(?i)([a-z][a-z0-9+.-]*://)[^/@\s]+:[^/@\s]+@', '$1[REDACTED]@'
    $result = $result -replace '(?i)\b([A-Z]:\\Users\\)[^\\\s"''<>|]+', '$1[USER_PROFILE]'
    $result = $result -replace '(?i)\b[A-Z]:\\[^\r\n\t"''<>|]+', '[REDACTED_PATH]'
    $result = $result -replace '(?i)\\\\[^\\\s]+\\[^\s"''<>|]+', '[REDACTED_PATH]'
    if(-not $NoTruncate -and $result.Length -gt 4096){$result=$result.Substring(0,4096)}
    return $result
}

function Get-WpaOutputDigest {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    $value = if($null -eq $Text){''}else{$Text}
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($value)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $digest = [Convert]::ToHexString($hash.ComputeHash($bytes)).ToLowerInvariant() } finally { $hash.Dispose() }
    [pscustomobject]@{ hash=$digest; length=$bytes.Length; truncated=$false }
}

function ConvertTo-WpaDiagnosticText {
    [CmdletBinding()]
    param([AllowNull()][string]$StdOut,[AllowNull()][string]$StdErr)
    $parts=@()
    if(-not [string]::IsNullOrEmpty($StdOut)){$parts+='stdout: '+(Protect-WpaSensitiveText $StdOut -NoTruncate)}
    if(-not [string]::IsNullOrEmpty($StdErr)){$parts+='stderr: '+(Protect-WpaSensitiveText $StdErr -NoTruncate)}
    $text=$parts -join [Environment]::NewLine
    $truncated=$text.Length -gt 4096
    if($truncated){$text=$text.Substring(0,4096)}
    [pscustomobject]@{ text=$text; truncated=$truncated }
}
