# Task 2 report — policy-scoped inventory and schema v2

## Status

Complete. The task commit is this commit (`feat: scope inventory to selected policy managers`); the final commit hash is reported by `git rev-parse HEAD` in the handoff.

## Implemented

- `Get-WpaInventoryAggregate` now requires a policy hash and explicit manager selection, normalizes/sorts the scope, invokes only selected adapters, emits schema v2 provenance, and computes status over the selected scope.
- `Get-WpaInventory -PolicyPath` is mandatory, validates the policy, hashes it canonically, and forwards the allowed manager scope and policy hash while preserving output and `ShouldProcess` behavior.
- `Get-WpaInventoryStateHash` now fails closed when schema-v2 provenance is missing/invalid and binds the canonical state to policy hash and sorted manager scope.
- Inventory schema and sample are v2 with a required lowercase SHA-256 policy hash and nonempty unique manager scope.
- Focused tests cover excluded-adapter protection, single-manager success/failure, empty scope rejection, public policy forwarding, provenance, state-hash drift, and schema validation.

## Changed files

- `schemas/inventory.schema.json`
- `src/WinPkgAgent/Private/Inventory/Aggregator.ps1`
- `src/WinPkgAgent/Public/Get-WpaInventory.ps1`
- `src/WinPkgAgent/Private/Core/Canonical.ps1`
- `tests/Unit/Inventory.Tests.ps1`
- `tests/Unit/Manifest.Tests.ps1`
- `examples/inventory.sample.json`

## TDD evidence

RED command:

```powershell
. .\tests\PesterConfiguration.ps1; $config = Get-WpaPesterConfiguration -Path './tests/Unit/Inventory.Tests.ps1','./tests/Unit/Manifest.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration $config
```

Result before implementation: 24 passed, 14 failed. Failures were the expected missing `-Managers`/provenance/schema-v2 behavior, not real manager execution.

GREEN command: the same command after implementation.

Result: 39 passed, 0 failed, 0 skipped.

## Verification and concerns

- `git diff --check`: passed; Git emitted only expected LF/CRLF normalization warnings.
- No real WinGet/Scoop package manager was invoked; all adapter coverage uses injected scriptblocks/mocks.
- The managed Pester run printed `Get-CimInstance: アクセスは拒否されました` during coverage metadata collection, while Pester still exited successfully with 39/39 tests passing. Coverage was 1.81% for this focused run and is not a task acceptance gate.
- Plane synchronization remains unavailable as recorded in `progress.md` (`Transport closed` in the parent session); no Plane state was claimed or changed.
- No package mutation, privilege, PATH, execution-policy, App Installer, fallback, or manager-remapping path was added.
