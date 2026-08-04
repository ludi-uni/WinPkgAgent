function Protect-WpaSensitiveText {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return $null }
    $result = $Text -replace '(?i)(authorization\s*:\s*bearer\s+)\S+', '$1[REDACTED]'
    $result = $result -replace '(?i)\b(token|password|secret|api[_-]?key)\s*[=:]\s*[^\s,;]+', '$1=[REDACTED]'
    $result = $result -replace '(?i)([a-z][a-z0-9+.-]*://)[^/@\s]+:[^/@\s]+@', '$1[REDACTED]@'
    $result = $result -replace '(?i)\b[A-Z]:\\[^\r\n\t"''<>|]+', '[REDACTED_PATH]'
    $result = $result -replace '(?i)\\\\[^\\\s]+\\[^\s"''<>|]+', '[REDACTED_PATH]'
    if($result.Length -gt 4096){$result=$result.Substring(0,4096)}
    return $result
}
