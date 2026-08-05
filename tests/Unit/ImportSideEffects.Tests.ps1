Describe 'module import side effects' {
    It 'does not change PATH while importing the module' {
        $modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
        $before = $env:Path
        try {
            Import-Module $modulePath -Force
            $env:Path | Should -Be $before
        } finally {
            Remove-Module WinPkgAgent -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not invoke manager resolution or write files while importing' {
        $sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../src/WinPkgAgent'))
        $fixtureRoot = Join-Path $TestDrive 'import-fixture'
        [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixtureRoot 'marker.txt'), 'fixture')
        $getFixtureSnapshot = {
            $fixtureRootFull = [IO.Path]::GetFullPath($fixtureRoot)
            $files = @()
            $reparsePoints = @()
            $exists = Test-Path -LiteralPath $fixtureRootFull -PathType Container
            if($exists) {
                $items = @((Get-Item -LiteralPath $fixtureRootFull -Force)) + @(Get-ChildItem -LiteralPath $fixtureRootFull -Force -Recurse)
                foreach($item in $items) {
                    $itemFull = [IO.Path]::GetFullPath($item.FullName)
                    $relative = [IO.Path]::GetRelativePath($fixtureRootFull, $itemFull)
                    if([IO.Path]::IsPathFullyQualified($relative) -or $relative -eq '..' -or $relative -like '..\*' -or $relative -like '../*') {
                        throw 'Fixture snapshot escaped its root.'
                    }
                    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        $reparsePoints += $relative
                    }
                    if(-not $item.PSIsContainer) {
                        $files += [pscustomobject]@{
                            Path = $relative
                            Length = $item.Length
                            Hash = (Get-FileHash -LiteralPath $itemFull -Algorithm SHA256).Hash
                        }
                    }
                }
            }
            return ([pscustomobject]@{
                Exists = $exists
                Files = @($files | Sort-Object Path)
                ReparsePoints = @($reparsePoints | Sort-Object)
            } | ConvertTo-Json -Compress -Depth 5)
        }

        $probeModuleRoot = Join-Path $TestDrive 'WinPkgAgent'
        [IO.Directory]::CreateDirectory($probeModuleRoot) | Out-Null
        $probePsm1 = Join-Path $probeModuleRoot 'WinPkgAgent.psm1'
        $probePsd1 = Join-Path $probeModuleRoot 'WinPkgAgent.psd1'
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'Private') -Destination $probeModuleRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'Public') -Destination $probeModuleRoot -Recurse
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'WinPkgAgent.psm1') -Destination (Join-Path $probeModuleRoot 'Loader.ps1')
        @"
`$script:ImportGetCommandCalls = 0
function Get-Command {
    `$script:ImportGetCommandCalls++
    throw 'Import manager-resolution seam called.'
}
`$script:ImportProcessCalls = 0
`$script:WpaProcessFactory = {
    `$script:ImportProcessCalls++
    throw 'Import process seam called.'
}
. (Join-Path `$PSScriptRoot 'Loader.ps1')
"@ | Set-Content -LiteralPath $probePsm1 -Encoding utf8
        @"
@{
    RootModule = 'WinPkgAgent.psm1'
    ModuleVersion = '1.0.0'
    GUID = '8a1d7e62-8d7c-4f95-bb2e-9bd3a9b0ce5d'
    FunctionsToExport = '*'
}
"@ | Set-Content -LiteralPath $probePsd1 -Encoding utf8

        $beforePath = $env:Path
        $beforeFixture = & $getFixtureSnapshot
        try {
            Import-Module $probePsd1 -Force
            $env:Path | Should -Be $beforePath
            InModuleScope WinPkgAgent {
                $script:ImportGetCommandCalls | Should -Be 0
                $script:ImportProcessCalls | Should -Be 0
            }
            $afterFixture = & $getFixtureSnapshot
            $afterFixture | Should -Be $beforeFixture
            ($afterFixture | ConvertFrom-Json).ReparsePoints.Count | Should -Be 0
        } finally {
            Remove-Module WinPkgAgent -Force -ErrorAction SilentlyContinue
        }
    }
}
