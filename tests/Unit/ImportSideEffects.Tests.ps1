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

    It 'does not invoke manager processes or write artifacts while importing' {
        $modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
        $artifactRoot = Join-Path $PSScriptRoot '../../artifacts'
        $getArtifactSnapshot = {
            if(-not (Test-Path -LiteralPath $artifactRoot)) { return '[]' }
            $files = @(Get-ChildItem -LiteralPath $artifactRoot -File -Recurse | ForEach-Object {
                [pscustomobject]@{
                    Path = $_.FullName.Substring($artifactRoot.Length).TrimStart('\','/')
                    Length = $_.Length
                    Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                }
            } | Sort-Object Path)
            if($files.Count -eq 0) { return '[]' }
            return ($files | ConvertTo-Json -Compress)
        }
        $before = & $getArtifactSnapshot

        try {
            Mock Invoke-WpaProcess { throw 'Import side-effect process call' } -ModuleName WinPkgAgent
            Mock Resolve-WpaManagerExecutable { throw 'Import side-effect resolver call' } -ModuleName WinPkgAgent
            Import-Module $modulePath -Force
            Should -Invoke Invoke-WpaProcess -Times 0 -Exactly
            Should -Invoke Resolve-WpaManagerExecutable -Times 0 -Exactly
            $after = & $getArtifactSnapshot
            $after | Should -Be $before
        } finally {
            Remove-Module WinPkgAgent -Force -ErrorAction SilentlyContinue
        }
    }
}
