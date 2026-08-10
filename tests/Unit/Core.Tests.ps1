$modulePath = Join-Path $PSScriptRoot '../../src/WinPkgAgent/WinPkgAgent.psd1'
Import-Module $modulePath -Force

Describe 'WinPkgAgent canonical data and validation' {
    InModuleScope WinPkgAgent {
        It 'produces identical canonical JSON for differently ordered properties' {
            $left = [pscustomobject]@{ z = 1; a = [pscustomobject]@{ y = 2; x = 3 } }
            $right = [pscustomobject]@{ a = [pscustomobject]@{ x = 3; y = 2 }; z = 1 }
            (ConvertTo-WpaCanonicalJson $left) | Should -Be (ConvertTo-WpaCanonicalJson $right)
        }

        It 'redacts credentials, tokens, and user profile paths' {
            $text = 'token=secret123 Authorization: Bearer abc C:\Users\alice\private.txt'
            $redacted = Protect-WpaSensitiveText $text
            $redacted | Should -Not -Match 'secret123|Bearer abc|alice'
        }

        It 'redacts URL credentials, arbitrary absolute paths, and bounds persisted diagnostics' {
            $text=('https://alice:secret@example.test C:\Work\private\file.txt ' + ('x' * 10000))
            $redacted=Protect-WpaSensitiveText $text
            $redacted | Should -Not -Match 'alice:secret'
            $redacted | Should -Not -Match 'C:\\Work\\private'
            $redacted.Length | Should -BeLessOrEqual 4096
        }

        It 'rejects unsafe package identifiers' {
            { Assert-WpaPackageIdentifier -Value 'safe; calc.exe' -Manager winget } | Should -Throw
        }

        It 'rejects parent traversal in artifact paths before creating anything' {
            { Assert-WpaSafeOutputPath -Path '../escape.json' } | Should -Throw '*traversal*'
        }

        It 'creates a stable inventory state hash without collection timestamps' {
            $one = [pscustomobject]@{ schemaVersion=2; policyHash=('a' * 64); managerScope=@('winget'); environment = @{ id = 'env' }; managers = @(@{ manager='winget'; status='success'; version='1.0' }); packages=@(@{ manager='winget'; id='A.B'; installedVersion='1.0'; availableVersion=$null; source='winget'; scope='user' }); collectedAt='2026-01-01T00:00:00Z' }
            $two = $one.PSObject.Copy(); $two.collectedAt = '2026-02-01T00:00:00Z'
            (Get-WpaInventoryStateHash $one) | Should -Be (Get-WpaInventoryStateHash $two)
        }

        It 'keeps hashes stable across an ISO timestamp JSON round trip' {
            $value=[pscustomobject]@{createdAt='2026-08-04T00:00:00.0000000+00:00';items=@()}
            $before=Get-WpaObjectHash $value
            $after=Get-WpaObjectHash (($value|ConvertTo-Json -Depth 10)|ConvertFrom-Json)
            $after | Should -Be $before
        }
    }
}
