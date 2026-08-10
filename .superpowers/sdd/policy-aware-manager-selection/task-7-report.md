# Task 7 fixture closure report

## Status

Complete. The four inventory schema-v2 fixture failures are closed without changing production source or the three baseline-failing tests.

## Verification counts

- Bounded suites before the fix: 19 passed, 4 failed, 0 skipped across 23 tests.
- Bounded suites after the fix: 23 passed, 0 failed, 0 skipped.
- Full safe `tests` suite after the fix: 183 passed, 3 failed, 0 skipped across 186 tests.
- The remaining three full-suite failures are the documented baseline failures: empty WinGet export parsing, empty Scoop export parsing, and package-migration candidate formatting.
- Coverage: 75.07%, meeting the configured 75% threshold.

## Changes

- Updated Core, DiagnosticLogging, and ManagerFingerprint inventory fixtures to schema v2 with valid policy hashes and manager scopes matching their manager records.
- Updated the UnmanagedObservations inventory JSON fixture with schema v2, a valid 64-hex policy hash, and `winget` manager scope.
- No production source, baseline-failing test, package semantics, or real manager path was changed.

## Commands

- Four closest suites with `Get-WpaPesterConfiguration -DisableRegistry`: 23 passed, 0 failed.
- Full `tests` suite with `Get-WpaPesterConfiguration -DisableRegistry`: 183 passed, 3 documented baseline failures.
- `git diff --check`: passed.

## Concerns and limitations

- Pester reports `Get-CimInstance` access-denied warnings while writing environment metadata in this managed test host.
- The full-suite command returns a failing status because the three pre-existing baseline tests remain unchanged, as required.

## Final verification fix round 1

- Corrected `examples/inventory.sample.json` to the default policy hash `1756ff7ed2d3e16b1b0d153edcd85f7d2bb96f7f404b91ae5dfcacc90c6f0fd5`.
- Added deterministic, schema-valid trusted/valid fingerprints for both `winget` and `scoop`, including fixed hashes, timestamps, lengths, and `isReparsePoint: false`.
- Schema/sample validation: passed.
- Full safe `tests` suite: 183 passed, 3 unchanged baseline failures.
- Fixture-only plan CLI `-WhatIf`: passed without writing `TestResults/whatif-plan.json`.
- `git diff --check`: passed.
