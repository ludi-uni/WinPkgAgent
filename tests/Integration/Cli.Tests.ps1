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

    It 'documents explicit policy-scoped inventory and fail-closed migration guidance' {
        $docs = @(
            (Get-Content (Join-Path $root 'README.md') -Raw),
            (Get-Content (Join-Path $root 'README.ja.md') -Raw),
            (Get-Content (Join-Path $root 'docs/usage.md') -Raw),
            (Get-Content (Join-Path $root 'docs/usage.ja.md') -Raw),
            (Get-Content (Join-Path $root 'docs/architecture.md') -Raw),
            (Get-Content (Join-Path $root 'docs/architecture.ja.md') -Raw),
            (Get-Content (Join-Path $root 'docs/troubleshooting.md') -Raw)
        ) -join "`n"

        $docs | Should -Match 'Get-WpaInventory[\s\S]*-PolicyPath[\s\S]*config/policy\.codex\.yaml'
        $docs | Should -Match 'config/policy\.(desktop|default)\.yaml'
        $docs | Should -Match 'policyHash'
        $docs | Should -Match 'managerScope'
        $docs | Should -Match 'schema v2'
        $docs | Should -Match 'INVENTORY_SCOPE_MISMATCH'
        $docs | Should -Match 'MANAGER_NOT_ALLOWED'
        $docs | Should -Match 'MANAGER_UNAVAILABLE'
        $docs | Should -Match 'resume-verify[\s\S]*-PolicyPath'

        $samplePath = Join-Path $root 'examples/inventory.sample.json'
        $sample = Get-Content $samplePath -Raw | ConvertFrom-Json
        $sample.schemaVersion | Should -Be 2
        (Test-Json -Path $samplePath -SchemaFile (Join-Path $root 'schemas/inventory.schema.json')) | Should -BeTrue
    }
}
