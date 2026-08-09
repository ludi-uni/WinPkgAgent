Describe 'winpkg-agent CLI' {
    BeforeAll {
        $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $cli = Join-Path $root 'scripts/winpkg-agent.ps1'
        $module = Join-Path $root 'src/WinPkgAgent/WinPkgAgent.psd1'
        . (Join-Path $root 'scripts/Private/Preview.ps1')
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

    It 'summarizes a blocked plan without invoking approval or apply' {
        Mock New-WpaRun { [pscustomobject]@{runId='20260809-010203-aabbccdd'} }
        Mock Test-WpaPlan { [pscustomobject]@{valid=$true;errors=@()} }
        Mock Get-Content { '{"actions":[],"blockedOperations":[{"manager":"winget","id":"Vendor.Tool","reasonCode":"MANAGER_NOT_ALLOWED","reason":"manager is not allowed","secret":"must not leak"}],"warnings":[]}' }
        Mock Approve-WpaRun { throw 'approval must not run' }
        Mock Invoke-WpaRun { throw 'apply must not run' }

        $result = Invoke-WpaCliPreview -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $TestDrive

        $result.PSObject.Properties.Name | Should -Be @('status','runId','runPath','actionCount','blockedCount','warningCount','blockedReasons','nextCommand')
        $result.status | Should -Be 'blocked'
        $result.blockedCount | Should -Be 1
        $result.blockedReasons[0].PSObject.Properties.Name | Should -Be @('manager','id','reasonCode','reason')
        $result.blockedReasons[0].reasonCode | Should -Be 'MANAGER_NOT_ALLOWED'
        $result.blockedReasons[0].PSObject.Properties.Name | Should -Not -Contain 'secret'
        $result.nextCommand | Should -Match 'approve-run'
        Should -Invoke New-WpaRun -Times 1 -Exactly
        Should -Invoke Test-WpaPlan -Times 1 -Exactly
        Should -Invoke Approve-WpaRun -Times 0 -Exactly
        Should -Invoke Invoke-WpaRun -Times 0 -Exactly
    }

    It 'summarizes a ready plan with counts and a safe single-quoted command' {
        Mock New-WpaRun { [pscustomobject]@{runId='20260809-010203-aabbccdd'} }
        Mock Test-WpaPlan { [pscustomobject]@{valid=$true;errors=@()} }
        Mock Get-Content { '{"actions":[{},{}],"blockedOperations":[],"warnings":[{},{}]}' }

        $result = Invoke-WpaCliPreview -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath (Join-Path $TestDrive "o'hare")

        $result.status | Should -Be 'ready'
        $result.actionCount | Should -Be 2
        $result.blockedCount | Should -Be 0
        $result.warningCount | Should -Be 2
        $result.nextCommand | Should -BeExactly ("pwsh ./scripts/winpkg-agent.ps1 approve-run -RunPath '{0}\o''hare\runs\20260809-010203-aabbccdd'" -f $TestDrive)
    }

    It 'fails closed on invalid plans before reading JSON or invoking mutation commands' {
        Mock New-WpaRun { [pscustomobject]@{runId='20260809-010203-aabbccdd'} }
        Mock Test-WpaPlan { [pscustomobject]@{valid=$false;errors=@('PLAN_SCHEMA_INVALID','raw path must not escape')} }
        Mock Get-Content { throw 'plan JSON must not be read' }
        Mock Approve-WpaRun { throw 'approval must not run' }
        Mock Invoke-WpaRun { throw 'apply must not run' }

        { Invoke-WpaCliPreview -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $TestDrive } |
            Should -Throw 'PREVIEW_PLAN_INVALID'
        Should -Invoke Get-Content -Times 0 -Exactly
        Should -Invoke Approve-WpaRun -Times 0 -Exactly
        Should -Invoke Invoke-WpaRun -Times 0 -Exactly
    }

    It 'returns the WhatIf projection without reading or validating a plan' {
        Mock New-WpaRun { [pscustomobject]@{runPath=(Join-Path $TestDrive 'runs/projected')} }
        Mock Test-WpaPlan { throw 'plan validation must not run' }
        Mock Get-Content { throw 'plan JSON must not be read' }
        Mock Approve-WpaRun { throw 'approval must not run' }
        Mock Invoke-WpaRun { throw 'apply must not run' }

        $result = Invoke-WpaCliPreview -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $TestDrive -WhatIf

        $result.status | Should -Be 'what-if'
        $result.runId | Should -BeNullOrEmpty
        $result.runPath | Should -Be (Join-Path $TestDrive 'runs/projected')
        $result.actionCount | Should -Be 0
        $result.blockedCount | Should -Be 0
        $result.warningCount | Should -Be 0
        $result.blockedReasons | Should -BeNullOrEmpty
        $result.nextCommand | Should -BeNullOrEmpty
        Should -Invoke New-WpaRun -Times 1 -Exactly
        Should -Invoke Test-WpaPlan -Times 0 -Exactly
        Should -Invoke Get-Content -Times 0 -Exactly
        Should -Invoke Approve-WpaRun -Times 0 -Exactly
        Should -Invoke Invoke-WpaRun -Times 0 -Exactly
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

        $docs | Should -Match 'winpkg-agent\.ps1 preview[\s\S]*packages\.example\.yaml[\s\S]*policy\.codex\.yaml'
        $docs | Should -Match 'preview[\s\S]*packages\.example\.yaml[\s\S]*policy\.(desktop|default)\.yaml'
        $docs | Should -Match 'blockedReasons'
        $docs | Should -Match 'exit code 2|終了コード.*2'
        $docs | Should -Match 'show-run[\s\S]*approve-run[\s\S]*invoke-run[\s\S]*WhatIf'
        $docs | Should -Match 'never approves|承認.*行いません'
        $docs | Should -Match 'PREVIEW_STAGING_PRESERVED'
        $docs | Should -Match 'inspect[\s\S]*manually|手動[\s\S]*確認'

        $samplePath = Join-Path $root 'examples/inventory.sample.json'
        $sample = Get-Content $samplePath -Raw | ConvertFrom-Json
        $sample.schemaVersion | Should -Be 2
        (Test-Json -Path $samplePath -SchemaFile (Join-Path $root 'schemas/inventory.schema.json')) | Should -BeTrue
    }
}
