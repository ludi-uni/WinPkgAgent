Describe 'manager contract parsers' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }

    It 'prefers a manager executable resolved from PATH' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { [pscustomobject]@{ Path = 'C:\tools\scoop.cmd' } }
            Resolve-WpaManagerExecutable -Manager scoop | Should -Be 'C:\tools\scoop.cmd'
        }
    }

    It 'resolves the user Scoop shim when it is absent from PATH' {
        InModuleScope WinPkgAgent {
            $oldUserProfile = $env:USERPROFILE
            try {
                $env:USERPROFILE = 'C:\Users\test'
                Mock Get-Command { $null }
                Mock Test-Path { param($LiteralPath) $LiteralPath -eq 'C:\Users\test\scoop\shims\scoop.cmd' }
                Resolve-WpaManagerExecutable -Manager scoop | Should -Be 'C:\Users\test\scoop\shims\scoop.cmd'
            } finally {
                $env:USERPROFILE = $oldUserProfile
            }
        }
    }

    It 'keeps a manager unavailable when no allowed candidate exists' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { $null }
            Mock Test-Path { $false }
            Resolve-WpaManagerExecutable -Manager winget | Should -BeNullOrEmpty
        }
    }

    It 'rejects a relative manager executable returned by command discovery' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { [pscustomobject]@{ Path = 'scoop.cmd'; Source = 'scoop.cmd' } }
            Resolve-WpaManagerExecutable -Manager scoop | Should -BeNullOrEmpty
        }
    }

    It 'returns an absolute manager executable path' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { [pscustomobject]@{ Path = 'C:\tools\scoop.cmd' } }
            $resolved = Resolve-WpaManagerExecutable -Manager scoop
            [System.IO.Path]::IsPathFullyQualified($resolved) | Should -BeTrue
        }
    }

    It 'rejects a relative FileName at the process boundary' {
        InModuleScope WinPkgAgent {
            { Invoke-WpaProcess -FilePath 'scoop.cmd' -Arguments @('--version') } | Should -Throw
        }
    }

    It 'parses winget export and rejects malformed data' {
        InModuleScope WinPkgAgent { $x=ConvertFrom-WpaWingetExport '{"Sources":[{"Packages":[{"PackageIdentifier":"Contoso.App","Version":"1.2.3"}]}]}'; $x[0].Id | Should -Be 'Contoso.App'; (ConvertFrom-WpaWingetExport '{bad') | Should -BeNullOrEmpty }
    }
    It 'parses scoop export' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaScoopExport '[{"name":"git","version":"2.45.1","bucket":"main"}]'; $x[0].Id | Should -Be 'git' } }
    It 'parses a winget upgrade row whose display name contains spaces' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaWingetUpgrade "Name              Id               Version  Available  Source`nMozilla Firefox   Mozilla.Firefox  128.0    129.0      winget"; $x.Valid | Should -BeTrue; $x.Items[0].Id | Should -Be 'Mozilla.Firefox'; $x.Items[0].AvailableVersion | Should -Be '129.0' } }
    It 'rejects an unknown winget upgrade locale' { InModuleScope WinPkgAgent { ConvertFrom-WpaWingetUpgrade "Paquet  Courant  Nouveau`noutil 1 2" | Should -BeNullOrEmpty } }
    It 'parses a scoop status row whose columns are aligned with spaces' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaScoopStatus "Name  Installed  Latest`ngit   2.45.0     2.46.0"; $x.Valid | Should -BeTrue; $x.Items[0].AvailableVersion | Should -Be '2.46.0' } }
    It 'builds scoop install spec as one literal argument' { InModuleScope WinPkgAgent { Mock Invoke-WpaProcess { [pscustomobject]@{ExitCode=0} }; Install-WpaScoopPackage -Id git -Version 2.45.1 -Source main; Assert-MockCalled Invoke-WpaProcess -ParameterFilter { $Arguments[1] -eq 'main/git@2.45.1' -and $Arguments[2] -eq '--no-update-scoop' } } }
    It 'accepts English and Japanese fallback headers only' { InModuleScope WinPkgAgent { (ConvertFrom-WpaWingetFallback "Name Version`nContoso.App 1.2.3").Count | Should -Be 1; (ConvertFrom-WpaWingetFallback "名前 バージョン`nContoso.App 1.2.3").Count | Should -Be 1; ConvertFrom-WpaWingetFallback 'Unknown locale output' | Should -BeNullOrEmpty } }
    It 'preserves special characters in display identifiers' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaWingetExport '{"Sources":[{"Packages":[{"PackageIdentifier":"Contoso.App_+Test","Version":"1.0"}]}]}'; $x[0].Id | Should -Be 'Contoso.App_+Test' } }
    It 'parses update metadata only with known locale headers' { InModuleScope WinPkgAgent { (ConvertFrom-WpaWingetUpgrade "Name  Id  Version  Available`nContoso App  Contoso.App  1.0  2.0").Items[0].AvailableVersion | Should -Be '2.0'; ConvertFrom-WpaWingetUpgrade 'x y z' | Should -BeNullOrEmpty } }
    It 'does not accept source agreements during read-only inventory' { InModuleScope WinPkgAgent { Mock Invoke-WpaProcess { [pscustomobject]@{ExitCode=1;TimedOut=$false;StdOut='';StdErr='';DurationMs=1} }; Get-WpaWingetInventory | Out-Null; Should -Invoke Invoke-WpaProcess -ParameterFilter { $Arguments -contains '--accept-source-agreements' } -Times 0 -Exactly } }
}
