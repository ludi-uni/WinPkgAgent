# Task 4 report: Align schemas, result samples, and CLI exit-code contracts

## Status

Implemented and verified. The existing exit-code implementation is `scripts/Private/ExitCode.ps1`, sourced by `scripts/winpkg-agent.ps1`; no parallel public API or replacement helper was added.

## Changes

- `schemas/apply-result.schema.json`: enforce lowercase 64-character SHA-256 patterns for operation output hashes and structural ISO 8601 timestamps for `startedAt` and `finishedAt`.
- `schemas/verify-result.schema.json`: enforce the same structural ISO 8601 timestamp contract for `verifiedAt`.
- `schemas/run.schema.json`: align run hashes and `createdAt` with the same strict contracts.
- `tests/Unit/Manifest.Tests.ps1`: enumerate and parse every `schemas/*.schema.json` file without a hard-coded count.
- `tests/Unit/ResultSchema.Tests.ps1`: correct result samples to 64-character hashes, add malformed-hash rejection coverage, retain malformed-timestamp rejection coverage, and test the existing CLI helper outside module scope.

## Verification

Command: bundled Pester 5.6.1, focused Manifest/ResultSchema/CLI paths, with `TestRegistry.Enabled = $false`.

Result: 30 passed, 0 failed, 0 skipped.

Command: parse every `schemas/*.schema.json` using `ConvertFrom-Json`.

Result: 8 schemas parsed successfully: `apply-result`, `approval`, `inventory`, `manifest`, `plan`, `policy`, `run`, and `verify-result`.

Additional check: `git diff --check` passed.

## Concerns and limitations

- Timestamp schema validation is structural ISO 8601 validation (date/time shape plus `Z` or numeric offset). No live package-manager or registry behavior is exercised by this focused run.
- The pre-existing untracked plan file was preserved unchanged.

## Review round 1 fixes

- `src/WinPkgAgent/Private/Schema/DataFiles.ps1` now performs semantic ISO 8601 validation on the serialized JSON after JSON Schema validation. It validates real calendar dates, clock ranges, fractional timestamps, and numeric offset ranges without losing offsets to PowerShell `DateTime` coercion.
- `tests/Unit/ResultSchema.Tests.ps1` now rejects `2026-02-30T00:00:00Z`, `2026-08-05T25:00:00Z`, `2026-08-05T23:60:00Z`, and `2026-08-05T23:59:59+99:99`; accepts `+09:30`, `-05:00`, and `+00:00`; and explicitly tests 63-, 64-, and 65-character hashes.
- The CLI helper architecture remains unchanged.

Exact review-round validation:

- Bundled Pester 5.6.1, `tests/Unit/ResultSchema.Tests.ps1`, TestRegistry disabled: 14 passed, 0 failed.
- Bundled Pester 5.6.1, Manifest/ResultSchema/CLI focused suite, TestRegistry disabled: 32 passed, 0 failed.
- JSON parsing of all 8 repository schemas: 8 passed.
- `git diff --check`: passed.
