# Task 3 report

Status: complete

Commit: containing commit (`feat: propagate policy scope through environment CLI`)

## Changed files

- `src/WinPkgAgent/Public/Test-WpaEnvironment.ps1`
- `src/WinPkgAgent/Public/Resume-WpaVerification.ps1`
- `scripts/winpkg-agent.ps1`
- `tests/Unit/Environment.Tests.ps1`
- `tests/Integration/Cli.Tests.ps1`

## Implementation

- `Test-WpaEnvironment -PolicyPath` now reads and validates the supplied policy, uses its runtime PowerShell path only when no explicit path is supplied, probes only declared managers, and requires every declared manager plus a compatible PowerShell runtime for readiness.
- Backwards-compatible environment inspection without `-PolicyPath` still probes both supported managers.
- `inventory` passes the explicit policy path to the mandatory `Get-WpaInventory` parameter.
- `Resume-WpaVerification` accepts mandatory `-PolicyPath` and passes it to inventory collection; the CLI forwards it.

## TDD evidence

- RED: the new focused suite first failed because excluded WinGet was probed, desktop readiness used an either-manager rule, invalid policy did not fail before probing, and CLI branches lacked policy propagation.
- GREEN: the required focused Pester command passed 8 tests with 0 failures and 0 skips.
- `git diff --check` passed.

## Concerns and limitations

- Pester code coverage reported 4.48% for the focused two-file run against the configured 75% threshold; this is a focused run, not a full-suite coverage claim.
- The run emitted existing managed `Get-CimInstance` access-denied warnings during coverage metadata collection.
- All manager availability was fixture/mock based. No real WinGet or Scoop calls ran.

## Fix round 1

- Reviewer finding: no-policy environment inspection incorrectly required both managers because the policy-scoped all-managers default was reused without a policy.
- RED: added `keeps no-policy readiness ready with either available manager`; the safe focused suite failed with expected `Expected $true, but got $false` while WinGet was unavailable and Scoop was available.
- GREEN: separated no-policy readiness (`winget -or scoop`) from policy-scoped all-allowed-manager readiness. The safe Environment/Cli Pester command passed 9 tests with 0 failures and 0 skips.
- No other Task 3 scope changed; manager availability remained fixture/mock based and no real manager calls ran.
