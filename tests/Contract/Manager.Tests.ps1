Describe 'manager contract parsers' {
    BeforeAll { Import-Module "$PSScriptRoot/../../src/WinPkgAgent/WinPkgAgent.psd1" -Force }

    It 'prefers an existing manager executable resolved from PATH' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'scoop.cmd'
            [IO.File]::WriteAllText($path, '@echo off')
            Mock Get-Command { [pscustomobject]@{ Path = $path } }
            Resolve-WpaManagerExecutable -Manager scoop | Should -Be ([IO.Path]::GetFullPath($path))
        }
    }

    It 'accepts an absolute Source-only command result when the file exists' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'winget.exe'
            [IO.File]::WriteAllText($path, 'fixture')
            Mock Get-Command { [pscustomobject]@{ Source = $path } }
            Resolve-WpaManagerExecutable -Manager winget | Should -Be ([IO.Path]::GetFullPath($path))
        }
    }

    It 'prefers the verified AppX executable over the WindowsApps alias' {
        InModuleScope WinPkgAgent {
            $installLocation = Join-Path $TestDrive 'Microsoft.DesktopAppInstaller'
            [IO.Directory]::CreateDirectory($installLocation) | Out-Null
            $wingetPath = Join-Path $installLocation 'winget.exe'
            [IO.File]::WriteAllText($wingetPath, 'fixture')
            $aliasPath = Join-Path $TestDrive 'Microsoft\WindowsApps\winget.exe'
            [IO.Directory]::CreateDirectory((Split-Path $aliasPath -Parent)) | Out-Null
            [IO.File]::WriteAllText($aliasPath, 'alias')
            $oldLocalAppData = $env:LOCALAPPDATA
            try {
                $env:LOCALAPPDATA = $TestDrive
                Mock Get-Command { [pscustomobject]@{ Path = $aliasPath } }
                Mock Get-AppxPackage { @([pscustomobject]@{ Name='Microsoft.DesktopAppInstaller'; InstallLocation=$installLocation }) }
                Resolve-WpaManagerExecutable -Manager winget | Should -Be ([IO.Path]::GetFullPath($wingetPath))
            } finally {
                $env:LOCALAPPDATA = $oldLocalAppData
            }
        }
    }

    It 'fails closed when AppX metadata is unavailable or ambiguous' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { $null }
            Mock Get-AppxPackage { @() }
            Resolve-WpaManagerExecutable -Manager winget | Should -BeNullOrEmpty
            Mock Get-AppxPackage { @(
                [pscustomobject]@{ Name='Microsoft.DesktopAppInstaller'; InstallLocation='C:\\Program Files\\WindowsApps\\one' }
                [pscustomobject]@{ Name='Microsoft.DesktopAppInstaller'; InstallLocation='C:\\Program Files\\WindowsApps\\two' }
            ) }
            Resolve-WpaManagerExecutable -Manager winget | Should -BeNullOrEmpty
        }
    }

    It 'fails closed when AppX InstallLocation is missing or unsafe' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { $null }
            Mock Get-AppxPackage { [pscustomobject]@{ Name='Microsoft.DesktopAppInstaller'; InstallLocation='relative-location' } }
            Resolve-WpaManagerExecutable -Manager winget | Should -BeNullOrEmpty
        }
    }

    It 'falls back to Source when Path is whitespace' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'scoop.cmd'
            [IO.File]::WriteAllText($path, '@echo off')
            Mock Get-Command { [pscustomobject]@{ Path = '  '; Source = $path } }
            Resolve-WpaManagerExecutable -Manager scoop | Should -Be ([IO.Path]::GetFullPath($path))
        }
    }
    It 'skips a Scoop PowerShell shim and resolves a process-compatible command shim' {
        InModuleScope WinPkgAgent {
            $ps1 = Join-Path $TestDrive 'scoop.ps1'
            $cmd = Join-Path $TestDrive 'scoop.cmd'
            [IO.File]::WriteAllText($ps1, 'Write-Output scoop')
            [IO.File]::WriteAllText($cmd, '@echo off')
            Mock Get-Command { @([pscustomobject]@{ Path = $ps1 }, [pscustomobject]@{ Path = $cmd }) }
            Resolve-WpaManagerExecutable -Manager scoop | Should -Be ([IO.Path]::GetFullPath($cmd))
        }
    }

    It 'ignores command results with neither Path nor Source' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { [pscustomobject]@{ Name = 'scoop' } }
            Mock Test-WpaVerifiedExecutablePath { $false }
            { Resolve-WpaManagerExecutable -Manager scoop } | Should -Not -Throw
            Resolve-WpaManagerExecutable -Manager scoop | Should -BeNullOrEmpty
        }
    }

    It 'resolves the user Scoop shim when it is absent from PATH' {
        InModuleScope WinPkgAgent {
            $oldUserProfile = $env:USERPROFILE
            try {
                $env:USERPROFILE = 'C:\Users\test'
                Mock Get-Command { $null }
                Mock Test-WpaVerifiedExecutablePath { param($Path) $Path -eq 'C:\Users\test\scoop\shims\scoop.cmd' }
                Resolve-WpaManagerExecutable -Manager scoop | Should -Be 'C:\Users\test\scoop\shims\scoop.cmd'
            } finally {
                $env:USERPROFILE = $oldUserProfile
            }
        }
    }

    It 'keeps a manager unavailable when no allowed candidate exists' {
        InModuleScope WinPkgAgent {
            Mock Get-Command { $null }
            Mock Get-AppxPackage { @() }
            Resolve-WpaManagerExecutable -Manager winget | Should -BeNullOrEmpty
        }
    }

    It 'rejects a relative manager executable returned by command discovery' {
        InModuleScope WinPkgAgent {
            $oldUserProfile = $env:USERPROFILE
            try {
                $env:USERPROFILE = Join-Path $TestDrive 'no-user-profile'
                Mock Get-Command { [pscustomobject]@{ Path = 'scoop.cmd'; Source = 'scoop.cmd' } }
                Mock Test-Path { $false }
                Resolve-WpaManagerExecutable -Manager scoop | Should -BeNullOrEmpty
            } finally {
                $env:USERPROFILE = $oldUserProfile
            }
        }
    }

    It 'returns an absolute manager executable path' {
        InModuleScope WinPkgAgent {
            $path = Join-Path $TestDrive 'scoop.cmd'
            [IO.File]::WriteAllText($path, '@echo off')
            Mock Get-Command { [pscustomobject]@{ Path = $path } }
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
    It 'accepts an empty winget export as an empty package set' {
        InModuleScope WinPkgAgent {
            $result = ConvertFrom-WpaWingetExport '{"Sources":[]}'
            $null -eq $result | Should -BeFalse
            $result | Should -HaveCount 0
        }
    }
    It 'parses scoop export' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaScoopExport '[{"name":"git","version":"2.45.1","bucket":"main"}]'; $x[0].Id | Should -Be 'git' } }
    It 'accepts an empty scoop export as an empty package set' {
        InModuleScope WinPkgAgent {
            $result = ConvertFrom-WpaScoopExport '{"buckets":[],"apps":[]}'
            $null -eq $result | Should -BeFalse
            $result | Should -HaveCount 0
        }
    }
    It 'rejects a Scoop table fallback with an unexpected trailing line' {
        InModuleScope WinPkgAgent {
            ConvertFrom-WpaScoopFallback "Name Version`ngit 2.45.1`nunexpected output extra" | Should -BeNullOrEmpty
        }
    }
    It 'rejects output before a Scoop table fallback header' {
        InModuleScope WinPkgAgent {
            ConvertFrom-WpaScoopFallback "unexpected output`nName Version`ngit 2.45.1" | Should -BeNullOrEmpty
        }
    }
    It 'parses the official multiline Scoop version output' {
        InModuleScope WinPkgAgent {
            $text = "Current Scoop version:`nv0.5.3 - Released at 2025-04-11`n`n'main' bucket:`n0123456 Update manifests"
            ConvertFrom-WpaScoopVersion $text | Should -Be '0.5.3'
        }
    }
    It 'rejects an incidental semantic version outside the official Scoop version shape' {
        InModuleScope WinPkgAgent {
            ConvertFrom-WpaScoopVersion "Current Scoop version:`n0123456 Update package to v9.9.9" | Should -BeNullOrEmpty
        }
    }
    It 'rejects output before the official Scoop version marker' {
        InModuleScope WinPkgAgent {
            $text = "unexpected output`nCurrent Scoop version:`nv0.5.3 - Released at 2025-04-11"
            ConvertFrom-WpaScoopVersion $text | Should -BeNullOrEmpty
        }
    }
    It 'rejects an unexpected suffix after the official Scoop release version' {
        InModuleScope WinPkgAgent {
            $text = "Current Scoop version:`nv0.5.3 - Released at 2025-04-11`nunrecognized trailing output"
            ConvertFrom-WpaScoopVersion $text | Should -BeNullOrEmpty
        }
    }
    It 'parses a winget upgrade row whose display name contains spaces' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaWingetUpgrade "Name              Id               Version  Available  Source`nMozilla Firefox   Mozilla.Firefox  128.0    129.0      winget"; $x.Valid | Should -BeTrue; $x.Items[0].Id | Should -Be 'Mozilla.Firefox'; $x.Items[0].AvailableVersion | Should -Be '129.0' } }
    It 'rejects an unknown winget upgrade locale' { InModuleScope WinPkgAgent { ConvertFrom-WpaWingetUpgrade "Paquet  Courant  Nouveau`noutil 1 2" | Should -BeNullOrEmpty } }
    It 'parses a scoop status row whose columns are aligned with spaces' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaScoopStatus "Name  Installed  Latest`ngit   2.45.0     2.46.0"; $x.Valid | Should -BeTrue; $x.Items[0].AvailableVersion | Should -Be '2.46.0' } }
    It 'parses the current Scoop status table columns' {
        InModuleScope WinPkgAgent {
            $text = "Name  Installed Version  Latest Version  Missing Dependencies  Info`ngit   2.45.0             2.46.0"
            $result = ConvertFrom-WpaScoopStatus $text
            $result.Valid | Should -BeTrue
            $result.Items[0].Id | Should -Be 'git'
            $result.Items[0].AvailableVersion | Should -Be '2.46.0'
        }
    }
    It 'rejects a header-only current Scoop status table' {
        InModuleScope WinPkgAgent {
            ConvertFrom-WpaScoopStatus 'Name  Installed Version  Latest Version  Missing Dependencies  Info' | Should -BeNullOrEmpty
        }
    }
    It 'rejects a header-only legacy Scoop status table' {
        InModuleScope WinPkgAgent {
            ConvertFrom-WpaScoopStatus 'Name  Installed  Latest' | Should -BeNullOrEmpty
        }
    }
    It 'rejects output before a current Scoop status header' {
        InModuleScope WinPkgAgent {
            $text = "unexpected output`nName  Installed Version  Latest Version  Missing Dependencies  Info`ngit   2.45.0             2.46.0"
            ConvertFrom-WpaScoopStatus $text | Should -BeNullOrEmpty
        }
    }
    It 'rejects a current Scoop status row that ends before the latest-version column' {
        InModuleScope WinPkgAgent {
            $text = "Name  Installed Version  Latest Version  Missing Dependencies  Info`ngit   2.45.0"
            ConvertFrom-WpaScoopStatus $text | Should -BeNullOrEmpty
        }
    }
    It 'treats a successful Scoop status with no installed apps as an empty update set' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '{"buckets":[],"apps":[]}'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Everything is ok!'; StdErr = '' }
            }
            $result = Get-WpaScoopInventory
            $result.status | Should -Be 'success'
            @($result.Packages) | Should -HaveCount 0
        }
    }
    It 'uses local-only Scoop status during inventory' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '{"buckets":[],"apps":[]}'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Everything is ok!'; StdErr = '' }
            }

            Get-WpaScoopInventory | Out-Null

            Should -Invoke Invoke-WpaProcess -Times 1 -Exactly -ParameterFilter {
                $Arguments.Count -eq 2 -and $Arguments[0] -eq 'status' -and $Arguments[1] -eq '--local' -and $NoTruncateOutput
            }
        }
    }
    It 'captures complete Scoop export output for parsing' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '{"buckets":[],"apps":[]}'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Everything is ok!'; StdErr = '' }
            }

            Get-WpaScoopInventory | Out-Null

            Should -Invoke Invoke-WpaProcess -Times 1 -Exactly -ParameterFilter {
                $Arguments.Count -eq 1 -and $Arguments[0] -eq 'export' -and $NoTruncateOutput
            }
        }
    }
    It 'accepts a complete known Scoop table fallback after a clean export' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = "Name Version`ngit 2.45.1"; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Everything is ok!'; StdErr = '' }
            }

            $result = Get-WpaScoopInventory

            $result.status | Should -Be 'success'
            $result.Packages | Should -HaveCount 1
            $result.Packages[0].id | Should -Be 'git'
        }
    }
    It 'rejects clean malformed Scoop export output' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'unrecognized output'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Everything is ok!'; StdErr = '' }
            }

            $result = Get-WpaScoopInventory

            $result.status | Should -Be 'failed'
            $result.Success | Should -BeFalse
            $result.Packages | Should -HaveCount 0
        }
    }
    It 'fails Scoop inventory when export emits stderr despite a zero exit code' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '{"buckets":[],"apps":[]}'; StdErr = 'fatal: detected dubious ownership' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Name  Installed  Latest'; StdErr = '' }
            }
            $result = Get-WpaScoopInventory
            $result.status | Should -Be 'failed'
            $result.Success | Should -BeFalse
            $result.warning | Should -Match 'stderr|unavailable|malformed'
        }
    }
    It 'fails Scoop inventory when export exits nonzero despite table-like stdout' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 1; TimedOut = $false; StdOut = "Name Version`ngit 2.45.1"; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Name  Installed  Latest'; StdErr = '' }
            }
            $result = Get-WpaScoopInventory
            $result.status | Should -Be 'failed'
            $result.Success | Should -BeFalse
            @($result.Packages) | Should -HaveCount 0
        }
    }
    It 'reports partial Scoop inventory when the version output is not numeric' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '[{"name":"git","version":"2.45.1","bucket":"main"}]'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Current Scoop version:'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Name  Installed  Latest'; StdErr = '' }
            }
            $result = Get-WpaScoopInventory
            $result.status | Should -Be 'partial'
            $result.Success | Should -BeTrue
            $result.warning | Should -Match 'version|status|unavailable|unrecognized'
        }
    }
    It 'reports partial Scoop inventory when the version probe emits stderr' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '[{"name":"git","version":"2.45.1","bucket":"main"}]'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = 'fatal: detected dubious ownership' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = 'Everything is ok!'; StdErr = '' }
            }

            $result = Get-WpaScoopInventory

            $result.status | Should -Be 'partial'
            $result.version | Should -BeNullOrEmpty
            $result.Success | Should -BeTrue
        }
    }
    It 'reports partial Scoop inventory when status output is empty for an empty export' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '{"buckets":[],"apps":[]}'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = ''; StdErr = '' }
            }
            $result = Get-WpaScoopInventory
            $result.status | Should -Be 'partial'
            $result.Success | Should -BeTrue
            $result.warning | Should -Match 'status|unavailable|unrecognized'
        }
    }
    It 'reports partial timed-out Scoop inventory when local status times out' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '[{"name":"git","version":"2.45.1","bucket":"main"}]'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = $null; TimedOut = $true; StdOut = 'Everything is ok!'; StdErr = '' }
            }

            $result = Get-WpaScoopInventory

            $result.status | Should -Be 'partial'
            $result.timedOut | Should -BeTrue
            $result.Success | Should -BeTrue
        }
    }
    It 'reports partial Scoop inventory when local status exits nonzero' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess {
                if ($Arguments[0] -eq 'export') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '[{"name":"git","version":"2.45.1","bucket":"main"}]'; StdErr = '' } }
                if ($Arguments[0] -eq '--version') { return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; StdOut = '0.5.3'; StdErr = '' } }
                [pscustomobject]@{ ExitCode = 1; TimedOut = $false; StdOut = 'Everything is ok!'; StdErr = '' }
            }

            $result = Get-WpaScoopInventory

            $result.status | Should -Be 'partial'
            $result.Success | Should -BeTrue
        }
    }
    It 'builds scoop install spec as one literal argument' {
        InModuleScope WinPkgAgent {
            Mock Resolve-WpaManagerExecutable { 'C:\fixtures\scoop.cmd' }
            Mock Invoke-WpaProcess { [pscustomobject]@{ ExitCode = 0 } }

            Install-WpaScoopPackage -Id git -Version 2.45.1 -Source main

            Assert-MockCalled Invoke-WpaProcess -ParameterFilter {
                $Arguments[1] -eq 'main/git@2.45.1' -and $Arguments[2] -eq '--no-update-scoop'
            }
        }
    }
    It 'accepts English and Japanese fallback headers only' { InModuleScope WinPkgAgent { (ConvertFrom-WpaWingetFallback "Name Version`nContoso.App 1.2.3").Count | Should -Be 1; (ConvertFrom-WpaWingetFallback "名前 バージョン`nContoso.App 1.2.3").Count | Should -Be 1; ConvertFrom-WpaWingetFallback 'Unknown locale output' | Should -BeNullOrEmpty } }
    It 'preserves special characters in display identifiers' { InModuleScope WinPkgAgent { $x=ConvertFrom-WpaWingetExport '{"Sources":[{"Packages":[{"PackageIdentifier":"Contoso.App_+Test","Version":"1.0"}]}]}'; $x[0].Id | Should -Be 'Contoso.App_+Test' } }
    It 'parses update metadata only with known locale headers' { InModuleScope WinPkgAgent { (ConvertFrom-WpaWingetUpgrade "Name  Id  Version  Available`nContoso App  Contoso.App  1.0  2.0").Items[0].AvailableVersion | Should -Be '2.0'; ConvertFrom-WpaWingetUpgrade 'x y z' | Should -BeNullOrEmpty } }
    It 'does not accept source agreements during read-only inventory' { InModuleScope WinPkgAgent { Mock Invoke-WpaProcess { [pscustomobject]@{ExitCode=1;TimedOut=$false;StdOut='';StdErr='';DurationMs=1} }; Get-WpaWingetInventory | Out-Null; Should -Invoke Invoke-WpaProcess -ParameterFilter { $Arguments -contains '--accept-source-agreements' } -Times 0 -Exactly } }
    It 'parses English and Japanese winget list rows with source-less identifiers' {
        InModuleScope WinPkgAgent {
            $english = @'
Name                 Id                         Version  Available  Source
-------------------  -------------------------  -------  ---------  ------
Ablaze Floorp         ARP\Machine\X64\Floorp     12.10.4
7-Zip                7zip.7zip                  25.01    26.02      winget
'@
            $japanese = @'
名前                 ID                         バージョン  利用可能  ソース
-------------------  -------------------------  ---------  --------  ------
Ablaze Floorp         ARP\Machine\X64\Floorp     12.10.4
7-Zip                7zip.7zip                  25.01     26.02     winget
'@
            $en = @(ConvertFrom-WpaWingetList -Text $english)
            $ja = @(ConvertFrom-WpaWingetList -Text $japanese)
            $en | Should -HaveCount 2
            $ja | Should -HaveCount 2
            $en[0].Id | Should -Be 'ARP\Machine\X64\Floorp'
            $en[0].Source | Should -BeNullOrEmpty
            $en[1].AvailableVersion | Should -Be '26.02'
            $ja[1].Source | Should -Be 'winget'
        }
    }
    It 'accepts a recognized empty winget list and rejects malformed rows' {
        InModuleScope WinPkgAgent {
            $empty = @'
Name                 Id                         Version  Available  Source
-------------------  -------------------------  -------  ---------  ------
'@
            $unknown = "Package Name  Identifier`n----"
            $malformed = @'
Name                 Id                         Version  Available  Source
-------------------  -------------------------  -------  ---------  ------
malformed row without enough columns
'@
            @(ConvertFrom-WpaWingetList -Text $empty) | Should -HaveCount 0
            ConvertFrom-WpaWingetList -Text $unknown | Should -BeNullOrEmpty
            ConvertFrom-WpaWingetList -Text $malformed | Should -BeNullOrEmpty
        }
    }
    It 'parses a long ARP identifier when it exceeds the header column width' {
        InModuleScope WinPkgAgent {
            $text = @'
Name                 Id                         Version  Available  Source
-------------------  -------------------------  -------  ---------  ------
NVIDIA Driver        ARP\Machine\X64\{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}_Display.Driver                 610.62
'@
            $rows = @(ConvertFrom-WpaWingetList -Text $text)
            $rows | Should -HaveCount 1
            $rows[0].Id | Should -Match 'Display\.Driver$'
            $rows[0].Version | Should -Be '610.62'
        }
    }
}
