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
        $modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
        $fixtureRoot = Join-Path $TestDrive 'import-fixture'
        [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixtureRoot 'marker.txt'), 'fixture')
        $getFixtureSnapshot = {
            $fixtureRootFull = [IO.Path]::GetFullPath($fixtureRoot)
            $files = @()
            $exists = Test-Path -LiteralPath $fixtureRootFull -PathType Container
            if($exists) {
                $files = @(Get-ChildItem -LiteralPath $fixtureRootFull -File -Recurse | ForEach-Object {
                    $fileFull = [IO.Path]::GetFullPath($_.FullName)
                    $relative = [IO.Path]::GetRelativePath($fixtureRootFull, $fileFull)
                    if([IO.Path]::IsPathFullyQualified($relative) -or $relative -eq '..' -or $relative -like '..\*' -or $relative -like '../*') {
                        throw 'Fixture snapshot escaped its root.'
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

        $beforePath = $env:Path
        $beforeFixture = & $getFixtureSnapshot
        Mock Get-Command { throw 'Import manager-resolution seam called' }
        try {
            Import-Module $modulePath -Force
            $env:Path | Should -Be $beforePath
            Should -Invoke Get-Command -Times 0 -Exactly
            $afterFixture = & $getFixtureSnapshot
            $afterFixture | Should -Be $beforeFixture
        } finally {
            Remove-Module WinPkgAgent -Force -ErrorAction SilentlyContinue
        }
    }
}
