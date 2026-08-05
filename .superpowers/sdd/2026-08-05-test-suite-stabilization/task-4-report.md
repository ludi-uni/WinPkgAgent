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
