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
        $before = if(Test-Path -LiteralPath $artifactRoot) {
            @(Get-ChildItem -LiteralPath $artifactRoot -File -Recurse | ForEach-Object FullName)
        } else { @() }

        try {
            Import-Module $modulePath -Force
            @(Get-Process -Name winget,scoop -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
            $after = if(Test-Path -LiteralPath $artifactRoot) {
                @(Get-ChildItem -LiteralPath $artifactRoot -File -Recurse | ForEach-Object FullName)
            } else { @() }
            $after | Should -Be $before
        } finally {
            Remove-Module WinPkgAgent -Force -ErrorAction SilentlyContinue
        }
    }
}
