# Task 2 report: manager and process adapter contracts

## Implementation

- `Resolve-WpaManagerExecutable` now reads optional command properties through `Get-WpaPropertyValue`, accepts only absolute existing leaf files, and returns normalized absolute paths. Missing `Path`/`Source` remains unavailable without throwing.
- `Invoke-WpaProcess` retains absolute-path rejection, `ProcessStartInfo.ArgumentList`, bounded termination wait, and structured result metadata. A private injected process runner seam allows contract tests to exercise argument and timeout contracts without invoking a host executable; injected output is redacted and bounded through the existing helper.
- Manager contract tests now use deterministic `$TestDrive` fixtures, cover Path-only, Source-only, missing-property, relative, and existing-file behavior, and do not discover or invoke real package managers.
- Process contract tests now use deterministic fixture paths and the injected runner rather than a real PowerShell path.
- Fingerprint tests use one named `-Manager`/`-Executable` parameter set and deterministic fixture files; the approval fixture includes the manager status/version fields required by the existing hash contract.

## Security and scope

- Absolute-path, leaf-file, reparse-point, signature, ACL, and Scoop forwarding checks were preserved.
- No PATH mutation, package installation, elevation, arbitrary external command, or real package-manager operation was added.
- `Winget.ps1` and `Scoop.ps1` required no task-local changes.
- The pre-existing untracked plan `docs/superpowers/plans/2026-08-05-test-suite-stabilization.md` was preserved.

## Exact validation

- Command: `$ErrorActionPreference='Continue'; Import-Module (Join-Path (Get-Location) '.tools/Pester/5.6.1/Pester.psd1') -Force; . './tests/PesterConfiguration.ps1'; $config=Get-WpaPesterConfiguration -Path @('./tests/Contract/Manager.Tests.ps1','./tests/Contract/Process.Tests.ps1','./tests/Unit/ManagerFingerprint.Tests.ps1') -DisableRegistry; $config.CodeCoverage.Enabled=$false; $config.TestResult.Enabled=$false; Invoke-Pester -Configuration $config`
  - Pester 5.6.1: 30 passed, 0 failed, 0 skipped; exit 0.
- Command: `$ErrorActionPreference='Continue'; Import-Module (Join-Path (Get-Location) '.tools/Pester/5.6.1/Pester.psd1') -Force; . './tests/PesterConfiguration.ps1'; $config=Get-WpaPesterConfiguration -Path @('./tests/Contract/Manager.Tests.ps1','./tests/Contract/Process.Tests.ps1','./tests/Unit/ManagerFingerprint.Tests.ps1') -DisableRegistry; $config.Output.Verbosity='None'; Invoke-Pester -Configuration $config; Write-Output "PesterExit=$LASTEXITCODE"`
  - Shared configuration with TestRegistry disabled: `PesterExit=0`; focused tests passed. The managed runner emitted three non-fatal `Get-CimInstance: アクセスは拒否されました` messages while Pester processed coverage/JUnit environment metadata.
- PowerShell parser validation for the five changed source/test files: passed.
- `git diff --check`: passed.

## Concerns

- The shared Pester configuration still enables coverage and JUnit output by default; this runner cannot query CIM environment metadata, so those non-fatal access-denied messages remain visible even though the test process exits 0.

## Commit

- Commit message: `fix: stabilize manager and process contracts`
