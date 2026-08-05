# Task 5 report

## Status

Complete. The import-side-effect and workspace tests now use canonical path handling and filesystem snapshots. No product code was changed because the reproduced failure was confined to the test snapshot helper.

## Changes

- `tests/Unit/ImportSideEffects.Tests.ps1`
  - Replaced artifact-root `Substring` path derivation with `IO.Path.GetFullPath()` and `IO.Path.GetRelativePath()` containment checks.
  - Snapshot now records artifact-root existence, relative file names, lengths, and SHA-256 hashes before and after import.
- `tests/Unit/Workspace.Tests.ps1`
  - Replaced raw prefix assertion with canonical relative-path and parent-directory containment assertions.
  - Added a reparse-point rejection fixture assertion.
  - Preserved traversal rejection through the existing outside-metadata test.

## Verification

- Bundled Pester `5.6.1`, `TestRegistry` disabled:
  - `ImportSideEffects.Tests.ps1` and `Workspace.Tests.ps1`: 6 passed, 0 failed.
- Direct absolute `pwsh.exe` import check with a temporary fixture:
  - `PathUnchanged=true`
  - `FixtureUnchanged=true`
  - `FixtureFileCount=1`
- Baseline reproduced the original failure at `ImportSideEffects.Tests.ps1:20`: `Substring` raised `ArgumentOutOfRangeException`.

The focused Pester run emitted the managed-environment `Get-CimInstance: access denied` coverage warning, but returned exit code 0. The pre-existing untracked plan was preserved.

## Review round 1 validation

- Import measurement now snapshots PATH and a `TestDrive` fixture before the measured `Import-Module -Force` call.
- `Get-Command` is explicitly mocked as the manager-resolution seam used by `Resolve-WpaManagerExecutable`; the import asserts exactly zero calls.
- Exact command:
  - `& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Import-Module './.tools/Pester/5.6.1/Pester.psd1'; . './tests/PesterConfiguration.ps1'; $config=Get-WpaPesterConfiguration -Path @('./tests/Unit/ImportSideEffects.Tests.ps1','./tests/Unit/Workspace.Tests.ps1') -DisableRegistry; Invoke-Pester -Configuration $config"`
- Result: Pester 5.6.1, 6 passed, 0 failed, 0 skipped; TestRegistry disabled. Coverage again emitted `Get-CimInstance: access denied` but the command exited 0.
- Traversal and reparse tests remained unchanged and passed.

## Review round 2 validation

- The measured probe imports the actual `WinPkgAgent.psm1` loader content and its `Private`/`Public` trees from a `TestDrive` copy. The probe module defines module-scope `Get-Command` and `WpaProcessFactory` sentinels before executing the loader; either seam throws immediately if invoked, and `InModuleScope WinPkgAgent` asserts both counters remain zero.
- The fixture snapshot now walks the fixture root and all descendants, records relative file hashes, and records reparse-point paths. The test asserts the before/after snapshot is identical and that the observed fixture has zero reparse points.
- Exact command:
  - `& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Import-Module './.tools/Pester/5.6.1/Pester.psd1'; . './tests/PesterConfiguration.ps1'; $config=Get-WpaPesterConfiguration -Path @('./tests/Unit/ImportSideEffects.Tests.ps1','./tests/Unit/Workspace.Tests.ps1') -DisableRegistry; Invoke-Pester -Configuration $config"`
- Result: Pester 5.6.1, 6 passed, 0 failed, 0 skipped; TestRegistry disabled. Coverage emitted the managed-environment `Get-CimInstance: access denied` warning, but the command exited 0.
