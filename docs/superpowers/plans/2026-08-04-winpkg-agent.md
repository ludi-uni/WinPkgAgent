# winpkg-agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a GitHub-ready PowerShell 7 module implementing the safe WinGet/Scoop inventory-to-verification workflow.

**Architecture:** Pure policy and planning functions are separated from adapters and artifact I/O. Public functions orchestrate explicit stages, while every external or mutating action crosses an injectable adapter boundary and is guarded by hashes, approval, environment, freshness, policy, and `ShouldProcess` checks.

**Tech Stack:** PowerShell 7.4+, powershell-yaml 0.4.12, JSON Schema 2020-12, Pester 5.x, PSScriptAnalyzer 1.25.x, GitHub Actions Windows runners.

## Global Constraints

- Workflow order is exactly `inventory -> plan -> approval -> apply -> verify`.
- v0.1 accepts only `state: present`; no uninstall path exists.
- No dependency is installed implicitly and no package operation is used by tests.
- WinGet and Scoop process calls use executable-plus-argument-array boundaries and explicit timeouts.
- Approval is interactive-only and separate from plan and apply.
- Unknown, stale, partial, ambiguous, or tampered state fails closed.

---

### Task 1: Repository contract, schemas, and samples

**Files:** Create `schemas/*.schema.json`, `config/*.yaml`, `profiles/*.yaml`, `.gitignore`, `.editorconfig`.

**Interfaces:** Schemas define manifest, policy, inventory, plan, approval, and result records consumed by every command.

- [x] Write failing schema/manifest tests for valid samples, missing fields, manager/state/id/path/policy rejection, and duplicates.
- [x] Run the focused Pester tests and confirm missing module/schema failures.
- [x] Add strict schemas, default policy, package example, and four profiles.
- [x] Re-run focused tests and validate every JSON schema with `Test-Json`.
- [x] Review for absent/uninstall fields and unsafe defaults.

### Task 2: Module loader, canonical data, validation, and safe I/O

**Files:** Create module manifests/loaders plus `Private/Schema`, `Private/Logging`, and core helpers.

**Interfaces:** Produce `Read-WpaYamlFile`, `Test-WpaDataSchema`, `ConvertTo-WpaCanonicalJson`, `Get-WpaSha256`, `Get-WpaEnvironmentId`, `Write-WpaAtomicJson`, and validation helpers.

- [x] Write failing tests for deterministic canonical JSON/hash, malformed/oversized input, traversal/reparse rejection, identifier validation, and redaction.
- [x] Run tests and confirm failures name the missing behavior.
- [x] Implement minimal helpers with bounded reads, ordinal property ordering, UTF-8 no-BOM atomic writes, and fail-closed validation.
- [x] Re-run focused tests, then refactor without changing contracts.

### Task 3: External command and manager adapters

**Files:** Create `Private/Adapters/Process.ps1`, `Winget.ps1`, `Scoop.ps1`, parsers, and fixtures.

**Interfaces:** `Invoke-WpaProcess` returns executable, arguments, exit code, stdout/stderr, duration, timeout; manager adapters expose detect, inventory, install, and upgrade operations.

- [x] Write failing tests for argument boundaries, timeout, exit metadata, malformed output, EN/JA fixtures, and manager feature detection.
- [x] Run focused contract tests and confirm expected failures.
- [x] Implement `ProcessStartInfo.ArgumentList` execution and machine-readable export-first adapters with strict fallback parsers.
- [x] Re-run tests and ensure no string shell or `Invoke-Expression` path exists.

### Task 4: Environment and inventory

**Files:** Create `Public/Test-WpaEnvironment.ps1`, `Public/Get-WpaInventory.ps1`, and `Private/Inventory/*`.

**Interfaces:** Inventory schema records manager status, packages, warnings, versions, collection time, and overall complete/partial/failed status.

- [x] Write failing tests for winget-only, scoop-only, both, neither, timeout, malformed output, partial success, special characters, and unmanaged reporting.
- [x] Run tests and confirm no production inventory implementation exists.
- [x] Implement environment capabilities and injected-adapter inventory aggregation.
- [x] Re-run focused tests and module import test.

### Task 5: Manifest, policy, and deterministic planning

**Files:** Create `Public/Test-WpaManifest.ps1`, `Public/New-WpaPlan.ps1`, `Public/Show-WpaPlan.ps1`, and `Private/Planning`, `Private/Policy`.

**Interfaces:** Planning classifies `no-op`, `install`, `upgrade`, `blocked`, `unmanaged`, and `unknown`, with stable reason codes and JSON/Markdown artifacts.

- [x] Write failing tests for duplicate ownership, install/no-op, patch/minor, blocked major/unknown/source/protected/incomplete, unmanaged reporting, max operations, and deterministic content hashes.
- [x] Run focused tests and verify each fails for missing behavior.
- [x] Implement merge validation, conservative version classification, policy gates, content/full hashes, and Markdown rendering.
- [x] Re-run tests with fixed clocks/IDs and compare literal expected reason codes.

### Task 6: Approval and plan validation

**Files:** Create `Public/Approve-WpaPlan.ps1`, `Public/Test-WpaPlan.ps1`, and `Private/Approval/*`.

**Interfaces:** Approval records the exact plan hash, approval/expiry time, and plan ID; test command validates plan integrity without mutation.

- [x] Write failing tests for noninteractive rejection, digest mismatch, tampering, expiry, environment mismatch, and schema errors.
- [x] Run focused tests and verify approval cannot be produced by another command.
- [x] Implement typed-digest interactive approval and reusable integrity validation.
- [x] Re-run tests; scan public parameters for force/bypass switches.

### Task 7: Apply and verify

**Files:** Create `Public/Invoke-WpaPlan.ps1`, `Private/Execution/*`, `Private/Verification/*`, and result renderers.

**Interfaces:** Apply returns ordered operation results and partial state; verify reports installed/version/PATH/manager/reboot/unknown outcomes.

- [x] Write failing tests for no approval, stale inventory/policy, manager loss, `-WhatIf` zero mutation calls, blocked actions, stop-after-failure, partial results, no reboot, successful/mismatched/PATH/manager verification.
- [x] Run focused tests and confirm failures are behavioral.
- [x] Implement complete preflight, sequential `ShouldProcess` execution, stop-on-failure, safe verification command arrays, reacquisition, and run summary.
- [x] Re-run focused and full tests; scan for uninstall/elevation/reboot verbs.

### Task 8: CLI, documentation, and CI

**Files:** Create `scripts/*.ps1`, `.github/workflows/ci.yml`, analyzer settings, README files, project governance, security and architecture documentation.

**Interfaces:** CLI dispatches public functions without duplicating business logic; bootstrap only reports/install instructions unless explicitly confirmed by a human.

- [x] Write failing CLI smoke/import/exported-command tests.
- [x] Run focused tests and confirm expected missing-entrypoint failures.
- [x] Implement CLI, build checks, pinned CI dependency installation, JUnit/coverage, English/Japanese docs, MIT license placeholder, AGENTS safety rules, and release/security guidance.
- [x] Run module import, schema/sample validation, analyzer, all Pester suites, and `-WhatIf` smoke.
- [x] Review all files for secrets, local paths, skipped tests, placeholders, unsafe options, and unimplemented README claims.

### Task 9: Integrated acceptance review

**Files:** Review the complete repository.

**Interfaces:** The mock workflow produces inventory, plan JSON/Markdown, validates separate approval, applies only approved actions, and verifies results.

- [x] Run the end-to-end fixture workflow and record generated artifacts outside version control.
- [x] Run analyzer, tests, schema validation, module-manifest parity, and CLI smoke from a clean PowerShell process.
- [x] Inspect the full diff and search for `Invoke-Expression`, uninstall, elevation, reboot, TODO, skipped tests, secrets, and machine-specific paths.
- [x] Record exact local versus mocked verification limits in the final report.


