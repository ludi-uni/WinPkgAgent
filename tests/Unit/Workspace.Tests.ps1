$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent run workspace boundaries' {
    InModuleScope WinPkgAgent {
        It 'maps only fixed artifact names inside the run directory' {
            $run=Join-Path $TestDrive 'runs/20260805-010203-aabbccdd';[IO.Directory]::CreateDirectory($run)|Out-Null
            $path=Get-WpaRunArtifactPath $run plan
            $runFull=[IO.Path]::GetFullPath($run)
            $pathFull=[IO.Path]::GetFullPath($path)
            [IO.Path]::GetRelativePath($runFull,$pathFull) | Should -Be 'plan.json'
            [IO.DirectoryInfo]::new((Split-Path -Parent $pathFull)).FullName | Should -Be ([IO.DirectoryInfo]::new($runFull)).FullName
            [IO.Path]::IsPathFullyQualified([IO.Path]::GetRelativePath($runFull,$pathFull)) | Should -BeFalse
        }

        It 'rejects run metadata that points outside the run directory' {
            $run=Join-Path $TestDrive 'run';[IO.Directory]::CreateDirectory($run)|Out-Null
            $metadata=[pscustomobject]@{schemaVersion=1;runId='20260805-010203-aabbccdd';manifestPath='../outside.yaml'}
            Write-WpaAtomicJson (Join-Path $run 'run.json') $metadata
            { Read-WpaRun $run } | Should -Throw
        }

        It 'rejects run paths containing reparse points' {
            $run=Join-Path $TestDrive 'reparse-run';[IO.Directory]::CreateDirectory($run)|Out-Null
            Mock Get-Item { [pscustomobject]@{Attributes=[IO.FileAttributes]::ReparsePoint} }
            { Get-WpaRunArtifactPath $run plan } | Should -Throw '*reparse*'
        }

        It 'exports the new high-level commands without approval bypasses' {
            (Get-Command New-WpaRun,Invoke-WpaRun,Resume-WpaVerification,Initialize-WpaProject,Export-WpaManifestCandidate).Count | Should -Be 5
            (Get-Command Invoke-WpaPlan).Parameters.Keys | Should -Not -Contain 'Force'
        }
    }
}
