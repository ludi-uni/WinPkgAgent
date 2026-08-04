$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'manager fingerprints' {
    InModuleScope WinPkgAgent {
        It 'returns artifact-safe fields and never the raw path' {
            $path=Join-Path $TestDrive 'winget.exe';[IO.File]::WriteAllText($path,'manager')
            $f=Get-WpaManagerFingerprint -Manager scoop -Executable ([IO.Path]::GetFullPath($path))
            @($f.PSObject.Properties.Name) | Should -Be @('manager','pathHash','fileSha256','fileVersion','lastWriteTimeUtc','fileLength','isReparsePoint','signatureStatus','signerSubject','aclAssessment')
            ($f | ConvertTo-Json) | Should -Not -Match [regex]::Escape($path)
            $f.pathHash | Should -Match '^[a-f0-9]{64}$';$f.fileSha256 | Should -Match '^[a-f0-9]{64}$'
        }
        It 'changes when executable content or metadata changes' {
            $path=Join-Path $TestDrive 'scoop.cmd';[IO.File]::WriteAllText($path,'echo one')
            $first=Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($path));Start-Sleep -Milliseconds 20;[IO.File]::WriteAllText($path,'echo two')
            $second=Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($path));$second.fileSha256 | Should -Not -Be $first.fileSha256
        }
        It 'rejects reparse-point files' {
            $path=Join-Path $TestDrive 'link.exe';Mock Get-Item { [pscustomobject]@{PSIsContainer=$false;Attributes=[IO.FileAttributes]::ReparsePoint;FullName=$path} }
            { Get-WpaManagerFingerprint scoop $path } | Should -Throw '*reparse*'
        }
        It 'rejects invalid or unavailable WinGet signatures' {
            $path=Join-Path $TestDrive 'winget.exe';[IO.File]::WriteAllText($path,'manager');Mock Get-AuthenticodeSignature { $null }
            $f=Get-WpaManagerFingerprint winget ([IO.Path]::GetFullPath($path));$f.signatureStatus | Should -Be 'unavailable'
        }
        It 'reports ACL availability as unknown when ACL inspection is unavailable' {
            $path=Join-Path $TestDrive 'acl.exe';[IO.File]::WriteAllText($path,'manager');Mock Get-Acl { throw 'unavailable' }
            (Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($path))).aclAssessment | Should -Be 'unknown'
        }
        It 'accepts a simple Scoop forwarding shim but marks complex syntax unavailable' {
            $target=Join-Path $TestDrive 'scoop.ps1';[IO.File]::WriteAllText($target,'target')
            $shim=Join-Path $TestDrive 'scoop.cmd';[IO.File]::WriteAllText($shim,'"'+([IO.Path]::GetFullPath($target))+'" %*')
            (Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($shim))).signatureStatus | Should -Be 'not-applicable'
            [IO.File]::WriteAllText($shim,'powershell -Command "'+([IO.Path]::GetFullPath($target))+'"')
            (Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($shim))).signatureStatus | Should -Be 'MANAGER_FINGERPRINT_UNAVAILABLE'
        }
    }
}
