function Assert-WpaSafeOutputPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if($Path -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Parent traversal segments are not accepted.'}
    $fullPath = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetFileName($fullPath) -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'Unsafe output file name.' }
    $parent = Split-Path $fullPath -Parent
    $cursor=$parent
    while($cursor -and -not (Test-Path -LiteralPath $cursor)){$next=Split-Path $cursor -Parent;if($next -eq $cursor){break};$cursor=$next}
    while($cursor){
        $parentItem=Get-Item -LiteralPath $cursor -Force
        if(($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse-point output directories are not accepted.'}
        $next=Split-Path $cursor -Parent;if($next -eq $cursor){break};$cursor=$next
    }
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    if (Test-Path -LiteralPath $fullPath) {
        $item = Get-Item -LiteralPath $fullPath -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Unsafe output target.' }
    }
    return $fullPath
}

function Write-WpaAtomicText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $fullPath = Assert-WpaSafeOutputPath -Path $Path
    $parent = Split-Path $fullPath -Parent
    $temporary = Join-Path $parent ('.wpa-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $fullPath, $true)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Write-WpaAtomicJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Data)
    Write-WpaAtomicText -Path $Path -Text (($Data | ConvertTo-Json -Depth 100) + [Environment]::NewLine)
}
