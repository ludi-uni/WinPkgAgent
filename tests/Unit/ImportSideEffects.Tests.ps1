Describe 'module import side effects' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
        Import-Module $modulePath -Force
    }

    AfterAll {
        Remove-Module WinPkgAgent -Force -ErrorAction SilentlyContinue
    }

    It 'does not change PATH while importing the module' {
        $before = $env:Path
        Import-Module $modulePath -Force
        $env:Path | Should -Be $before
    }

    It 'does not invoke manager processes or write artifacts while importing' {
        $artifactRoot = Join-Path $PSScriptRoot '../../artifacts'
        $getArtifactSnapshot = {
            $artifactRootFull = [IO.Path]::GetFullPath($artifactRoot)
            $files = @()
            $exists = Test-Path -LiteralPath $artifactRootFull -PathType Container
            if($exists) {
                $files = @(Get-ChildItem -LiteralPath $artifactRootFull -File -Recurse | ForEach-Object {
                    $fileFull = [IO.Path]::GetFullPath($_.FullName)
                    $relative = [IO.Path]::GetRelativePath($artifactRootFull, $fileFull)
                    if([IO.Path]::IsPathFullyQualified($relative) -or $relative -eq '..' -or $relative -like '..\*' -or $relative -like '../*') {
                        throw 'Artifact snapshot escaped its root.'
                    }
                    [pscustomobject]@{
                        Path = $relative
                        Length = $_.Length
                        Hash = (Get-FileHash -LiteralPath $fileFull -Algorithm SHA256).Hash
                    }
                } | Sort-Object Path)
            }
            return ([pscustomobject]@{Exists = $exists; Files = @($files)} | ConvertTo-Json -Compress -Depth 5)
        }

        $before = & $getArtifactSnapshot
        Import-Module $modulePath -Force
        $after = & $getArtifactSnapshot
        $after | Should -Be $before
    }
}
