Describe 'winpkg-agent CLI' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $cli = Join-Path $root 'scripts/winpkg-agent.ps1'
        $module = Join-Path $root 'src/WinPkgAgent/WinPkgAgent.psd1'
    }
    It 'exports exactly the documented public commands' {
        Import-Module $module -Force
        $actual = @((Get-Command -Module WinPkgAgent).Name | Sort-Object)
        $expected = @(@('Approve-WpaPlan','Get-WpaInventory','Invoke-WpaPlan','New-WpaPlan','Show-WpaPlan','Test-WpaEnvironment','Test-WpaManifest','Test-WpaPlan','New-WpaRun','Get-WpaRun','Show-WpaRun','Approve-WpaRun','Invoke-WpaRun','Resume-WpaVerification','Initialize-WpaProject','Export-WpaManifestCandidate','Export-WpaUnmanagedCandidate') | Sort-Object)
        $actual | Should -Be $expected
    }

    It 'can run the read-only environment command' {
        $output = & $cli environment
        $LASTEXITCODE | Should -Be 0
        $output | Should -Not -BeNullOrEmpty
    }

    It 'maps apply and verification outcomes to automation-safe exit codes' {
        . (Join-Path $root 'scripts/Private/ExitCode.ps1')
        Get-WpaCliExitCode -Command invoke -Result ([pscustomobject]@{apply=@{status='partial-failure'};verify=@{status='not-run'}}) | Should -Be 3
        Get-WpaCliExitCode -Command invoke -Result ([pscustomobject]@{apply=@{status='success'};verify=@{status='failed'}}) | Should -Be 4
        Get-WpaCliExitCode -Command invoke -Result ([pscustomobject]@{apply=@{status='success'};verify=@{status='reboot-required'}}) | Should -Be 5
    }

    It 'propagates policy paths through inventory and resume verification branches' {
        $script = Get-Content $cli

        $script | Should -Contain '        inventory { Get-WpaInventory -PolicyPath $PolicyPath -OutputPath $OutputPath -WhatIf:$WhatIf }'
        $script | Should -Contain "        'resume-verify' { Resume-WpaVerification -PlanPath `$PlanPath -ApplyResultPath `$ApplyResultPath -PolicyPath `$PolicyPath -VerifyOutputPath `$VerifyOutputPath -WhatIf:`$WhatIf }"
    }
}
