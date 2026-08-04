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
        It 'marks non-forwarding Scoop shims as unavailable fingerprint' {
            $path=Join-Path $TestDrive 'scoop-nonforward.cmd';[IO.File]::WriteAllText($path,'echo one')
            (Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($path))).signatureStatus | Should -Be 'MANAGER_FINGERPRINT_UNAVAILABLE'
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

        It 'marks a protected manager location trusted only after a conservative ACL check' {
            $path=Join-Path $TestDrive 'winget.exe';[IO.File]::WriteAllText($path,'manager')
            Mock Get-Acl { [pscustomobject]@{Owner='NT SERVICE\TrustedInstaller';Access=@()} }
            (Get-WpaManagerFingerprint winget ([IO.Path]::GetFullPath($path))).aclAssessment | Should -Be 'trusted;acl-checked'
        }

        It 'keeps a broadly writable manager location untrusted' {
            $path=Join-Path $TestDrive 'winget.exe';[IO.File]::WriteAllText($path,'manager')
            Mock Get-Acl { [pscustomobject]@{Owner='NT SERVICE\TrustedInstaller';Access=@([pscustomobject]@{AccessControlType='Allow';IdentityReference='BUILTIN\Users';FileSystemRights='Modify'})} }
            (Get-WpaManagerFingerprint winget ([IO.Path]::GetFullPath($path))).aclAssessment | Should -Be 'unknown'
        }
        It 'accepts a simple Scoop forwarding shim but marks complex syntax unavailable' {
            $target=Join-Path $TestDrive 'scoop.ps1';[IO.File]::WriteAllText($target,'target')
            $shim=Join-Path $TestDrive 'scoop.cmd';[IO.File]::WriteAllText($shim,'"'+([IO.Path]::GetFullPath($target))+'" %*')
            (Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($shim))).signatureStatus | Should -Be 'not-applicable'
            [IO.File]::WriteAllText($shim,'powershell -Command "'+([IO.Path]::GetFullPath($target))+'"')
            (Get-WpaManagerFingerprint scoop ([IO.Path]::GetFullPath($shim))).signatureStatus | Should -Be 'MANAGER_FINGERPRINT_UNAVAILABLE'
        }
        It 'maps lowercase unavailable fingerprint status to MANAGER_FINGERPRINT_UNAVAILABLE' {
            $fingerprint=[pscustomobject]@{manager='scoop';pathHash=('a'*64);fileSha256=('b'*64);fileVersion=$null;lastWriteTimeUtc='2026-01-01T00:00:00Z';fileLength=1;isReparsePoint=$false;signatureStatus='unavailable';signerSubject=$null;aclAssessment='trusted'}
            $action=[pscustomobject]@{name='tool';manager='scoop';id='tool';source='main';classification='install';operation='install';reasonCode='PACKAGE_NOT_INSTALLED';reason='missing';risk='low';targetVersion=$null;verification=$null}
            $plan=[pscustomobject][ordered]@{schemaVersion=1;toolVersion='0.1.0';planId=[guid]::NewGuid().ToString();createdAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z';environmentId='env';manifestHash=('a'*64);policyHash=$null;inventoryHash=$null;actions=@($action);blockedOperations=@();warnings=@();contentHash=$null;planHash=$null;managerFingerprints=@([pscustomobject]@{manager='scoop';fingerprint=$fingerprint})}
            $approval=[pscustomobject]@{schemaVersion=1;planId=$plan.planId;planHash=$null;approvedAt='2026-01-01T00:00:00Z';expiresAt='2099-01-01T00:00:00Z'}
            $inventory=[pscustomobject]@{schemaVersion=1;environment=@{id='env'};status='success';managers=@(@{manager='scoop';fingerprint=$fingerprint});packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
            $policy=[pscustomobject]@{schemaVersion=1;allowInstall=$true;allowUpgrade=@('patch','minor');allowUninstall=$false;allowedManagers=@('winget','scoop');allowedSources=@('winget','main');protectedPackages=@();dangerousCategories=@('driver');requireApproval=$true;approvalValidityMinutes=30;rejectStateChanges=$true;maxOperations=10;operationTimeoutSeconds=600;rebootHandling='record-only';unknownVersionHandling='block'}
            $plan.inventoryHash=Get-WpaInventoryStateHash $inventory
            $plan.policyHash=Get-WpaObjectHash $policy
            $plan.contentHash=Get-WpaObjectHash (Get-WpaPlanContent $plan)
            $plan.planHash=Get-WpaObjectHash (Get-WpaPlanHashInput $plan)
            $approval.planHash=$plan.planHash
            Mock Read-WpaJsonFile { if($Path -eq 'plan.json'){$plan}else{$approval} };Mock Test-WpaDataSchema { $true };Mock Get-WpaEnvironmentId {'env'};Mock Read-WpaPolicyFile {$policy};Mock Get-WpaInventory {$inventory};Mock Invoke-WpaManagerAction { throw 'must not run' }
            { Invoke-WpaPlan -PlanPath plan.json -ApprovalPath approval.json -PolicyPath policy.yaml -OutputPath $null -VerifyOutputPath $null -SummaryPath $null -Confirm:$false } | Should -Throw '*MANAGER_FINGERPRINT_UNAVAILABLE*'
        }
    }
}
