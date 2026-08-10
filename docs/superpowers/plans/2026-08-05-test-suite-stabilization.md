# Test Suite Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all existing WinPkgAgent contract, unit, integration, schema, and fixture-only smoke tests pass without weakening the fail-closed security model or making tests depend on the host's installed package managers.

**Architecture:** Stabilize the existing seams instead of adding a parallel test stack. Production code will normalize optional or legacy-shaped data at public boundaries, preserve conservative rejection for missing security evidence, and use absolute executable paths. Tests will use explicit fixtures and injected process behavior; no test will discover or mutate real packages. CI and the local runner will share one Pester configuration so environment-only capabilities such as registry-backed TestRegistry are explicit rather than accidental.

**Tech Stack:** PowerShell 7.4+, Pester 5.6.1, PSScriptAnalyzer 1.25.0, JSON Schema, existing WinPkgAgent adapters and CLI.

## Completion Status (2026-08-09)

This file preserves the original 2026-08-05 implementation plan. The checkboxes below record its intended execution sequence; they are not an open-work queue.

The stabilization work landed in these principal commits:

- `6086ccd` and `68f43f4`: shared Pester configuration and registry-capability handling.
- `e181601`: manager and process contract stabilization.
- `691d853`: plan and inventory fixture normalization.
- `fd5a2f4`: result-schema and CLI contract alignment.
- `64e710a` and `375e6de`: path-robust import and workspace checks.
- `7de593b`: host-independent AppX discovery coverage for the WinGet resolver contract.

Fresh verification on merged local `main` at `7de593b` discovered and passed 285 of 285 Pester tests with 75.47% command coverage against the 75% threshold. Build validation and fixture-only plan/preview `-WhatIf` checks passed without package mutation or plan/workspace artifact creation. PSScriptAnalyzer 1.25.0 was unavailable locally and was not installed automatically; it remains an explicit CI or suitably provisioned environment gate.

## Global Constraints

- Preserve the fail-closed inventory → plan → approval → apply → verify workflow.
- Never install dependencies automatically, alter user or machine PATH, elevate, uninstall packages, reboot, add sources, or execute arbitrary commands.
- Tests and CI must use injected adapters/fixtures and must never mutate real packages.
- Unknown, partial, stale, ambiguous, or tampered state remains blocked.
- Manager ACL trust remains conservative; unknown ACL state is not silently trusted.
- PowerShell runtime discovery uses absolute `pwsh.exe` paths, never falls back to `powershell.exe`, and keeps raw runtime paths out of artifacts.
- Run-workspace artifacts remain inside the run directory and reject traversal and reparse points.

---

## Original Inventory Findings (2026-08-05)

The initial full Pester run discovered 118 tests, with 81 passed and 37 failed. The failures were grouped as follows:

1. `tests/Contract/Manager.Tests.ps1`, `tests/Contract/Process.Tests.ps1`, and `tests/Unit/ManagerFingerprint.Tests.ps1` expose unsafe property access, relative process paths, and test assumptions that are inconsistent with the absolute-path process contract.
2. `tests/Unit/ApprovalExecution.Tests.ps1`, `tests/Unit/Execution.Tests.ps1`, `tests/Unit/DiagnosticLogging.Tests.ps1`, and `tests/Unit/Planning.Tests.ps1` pass fixtures missing fields now read under StrictMode (`managerFingerprints`, `blockedOperations`, `inventory`, and related plan fields).
3. `tests/Unit/Inventory.Tests.ps1` and `tests/Unit/ManagerFingerprint.Tests.ps1` reveal status aggregation and fingerprint parameter-set regressions.
4. `tests/Unit/Manifest.Tests.ps1` and `tests/Unit/ResultSchema.Tests.ps1` have stale schema counts and sample payloads that violate current hash/timestamp contracts; one expected CLI helper is not exported or implemented.
5. `tests/Unit/ImportSideEffects.Tests.ps1` has a path-normalization assumption that fails for the current workspace layout; the test must assert module behavior without relying on a fixed path length.
6. The managed local runner cannot create Pester's registry-backed TestRegistry. This is an execution-environment limitation, not a product behavior; the shared runner must disable TestRegistry when registry access is unavailable while CI keeps the default capability where supported.

---

### Task 1: Establish a reproducible failure baseline and shared Pester configuration

**Files:**
- Create: `tests/PesterConfiguration.ps1`
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/build.ps1`
- Test: `tests/PesterConfiguration.Tests.ps1`

**Interfaces:**
- `Get-WpaPesterConfiguration -Path <string[]> -DisableRegistry` returns a `PesterConfiguration` with paths, JUnit output, coverage settings, and an explicit TestRegistry setting.
- CI and `scripts/build.ps1` consume the same configuration shape.

- [ ] Add a configuration test that asserts the requested test paths, Pester 5.6.1-compatible properties, and explicit registry behavior.
- [ ] Run the configuration test with the local bundled Pester and record the baseline failure count.
- [ ] Update CI and build validation to use the shared configuration without changing dependency installation policy.
- [ ] Add capability detection that sets `TestRegistry.Enabled = $false` only when the current runner cannot write the Pester registry key; never grant elevation or write outside the test runner's allowed scope.
- [ ] Run the configuration test and the existing CLI tests.
- [ ] Commit as `test: centralize pester configuration`.

### Task 2: Repair manager and process adapter contracts

**Files:**
- Modify: `src/WinPkgAgent/Private/Adapters/ExecutableResolution.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Process.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Winget.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Scoop.ps1`
- Modify: `tests/Contract/Manager.Tests.ps1`
- Modify: `tests/Contract/Process.Tests.ps1`
- Modify: `tests/Unit/ManagerFingerprint.Tests.ps1`

**Interfaces:**
- `Resolve-WpaManagerExecutable -Manager winget|scoop` returns an absolute existing executable path or `$null`.
- `Invoke-WpaProcess -FilePath <absolute path> -Arguments <string[]> -TimeoutSeconds <int>` preserves argument boundaries and returns bounded metadata.
- `Get-WpaManagerFingerprint` accepts one stable parameter set and returns artifact-safe fingerprint fields.

- [ ] Add tests for mocked `Get-Command` results with missing `Path`, `Source`-only, relative, and absolute candidates.
- [ ] Replace real `pwsh` execution in the process contract with a fixture/injected process seam; retain one test that rejects relative paths before process start.
- [ ] Normalize missing mocked properties with `Get-WpaPropertyValue` instead of direct property access.
- [ ] Verify manager fingerprint tests use a deterministic fixture file and do not depend on Authenticode state of a host executable.
- [ ] Run manager, process, and fingerprint tests and require all to pass.
- [ ] Commit as `fix: stabilize manager and process contracts`.

### Task 3: Normalize plan, execution, diagnostic, and inventory fixture shapes

**Files:**
- Modify: `src/WinPkgAgent/Public/Invoke-WpaPlan.ps1`
- Modify: `src/WinPkgAgent/Public/New-WpaPlan.ps1`
- Modify: `src/WinPkgAgent/Private/Core/Canonical.ps1`
- Modify: `src/WinPkgAgent/Private/Core/Diagnostics.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Inventory.ps1`
- Modify: `tests/Unit/ApprovalExecution.Tests.ps1`
- Modify: `tests/Unit/Execution.Tests.ps1`
- Modify: `tests/Unit/DiagnosticLogging.Tests.ps1`
- Modify: `tests/Unit/Planning.Tests.ps1`
- Modify: `tests/Unit/Inventory.Tests.ps1`

**Interfaces:**
- Plan and inventory readers accept the current schema shape and safely default only non-security optional fields.
- Missing manager fingerprints, signature status, ACL assessment, or inventory identity remain explicit blocked outcomes.
- `ConvertTo-WpaDiagnosticText` always returns bounded text with deterministic truncation metadata.

- [ ] Add failing tests for incomplete plan/inventory objects and distinguish optional defaults from security-critical missing data.
- [ ] Normalize `managerFingerprints`, `blockedOperations`, and inventory collections at the boundary before StrictMode-sensitive access.
- [ ] Correct inventory status aggregation for scoop-only, winget-only, both-success, and failure combinations.
- [ ] Enforce the 4096-character diagnostic bound while preserving redaction behavior.
- [ ] Update fixture objects only where the schema intentionally requires a field; do not relax security validation.
- [ ] Run approval, execution, diagnostic, planning, and inventory tests.
- [ ] Commit as `fix: normalize plan and inventory fixture shapes`.

### Task 4: Align schemas, result samples, and CLI exit-code contracts

**Files:**
- Modify: `schemas/*.json` only where the implementation contract is intentionally corrected
- Modify: `tests/Unit/Manifest.Tests.ps1`
- Modify: `tests/Unit/ResultSchema.Tests.ps1`
- Modify: `src/WinPkgAgent/Private/Core/ExitCode.ps1` or the existing exit-code file if the helper is genuinely missing
- Modify: `tests/Integration/Cli.Tests.ps1` if expected exports are stale

**Interfaces:**
- Apply and verify result samples use 64-character SHA-256 hashes and ISO 8601 timestamps.
- `Get-WpaCliExitCode -Command <string> -Result <object>` is exported or tested through the supported CLI surface according to the existing architecture.
- Schema-count assertions enumerate the repository's actual schema contract rather than hard-coding a stale count.

- [ ] Add failing tests for short/long hashes, valid/invalid timestamps, default operation payloads, and CLI exit mapping.
- [ ] Fix the smallest schema or sample mismatch while retaining strict validation.
- [ ] Implement or correctly expose the exit-code helper only if the existing CLI design requires it; do not add a parallel public command unnecessarily.
- [ ] Run manifest, result-schema, and CLI tests.
- [ ] Commit as `fix: align result schemas and cli contracts`.

### Task 5: Make import-side-effect and workspace tests path-robust

**Files:**
- Modify: `tests/Unit/ImportSideEffects.Tests.ps1`
- Modify: `tests/Unit/Workspace.Tests.ps1` only if the same path-boundary issue is found
- Modify: `src/WinPkgAgent/Private/Core/Module.ps1` or the actual import path only if a product side effect is reproduced

**Interfaces:**
- Module import performs no manager process invocation, PATH mutation, package mutation, or artifact write.
- Workspace path tests assert containment and reparse rejection using path APIs, not fixed string offsets.

- [ ] Reproduce the current `Substring` failure with the test's exact path assumption.
- [ ] Replace fixed-index path parsing with `[IO.Path]` and `GetFullPath` comparisons.
- [ ] Add before/after PATH and filesystem snapshot assertions around module import.
- [ ] Run import-side-effect and workspace tests.
- [ ] Commit as `test: make import and workspace checks path robust`.

### Task 6: End-to-end verification and merge gate

**Files:**
- No additional files unless verification exposes a regression in the completed tasks.

- [ ] Run the closest test for each task, then the complete Pester suite using `tests/PesterConfiguration.ps1`.
- [ ] Run PSScriptAnalyzer 1.25.0 when it is already available and require zero errors; otherwise report the unavailable gate without installing it.
- [ ] Run the fixture-only CLI WhatIf smoke test and confirm no package manager process or artifact is invoked unexpectedly.
- [ ] Run module import PATH comparison and raw-path artifact scan.
- [ ] Review the full diff, generated test artifacts, and `git status`.
- [ ] Integrate only after the available suite, analyzer, smoke, and safety gates pass. Never push directly to `main`; use a Draft PR for remote review.

## Acceptance Criteria

- Full Pester suite passes with Pester 5.6.1 or newer.
- PSScriptAnalyzer reports zero errors when 1.25.0 is available; local unavailability is reported explicitly without automatic installation.
- Fixture-only CLI WhatIf smoke test succeeds without changing packages or PATH.
- Manager and process tests do not depend on real installed package managers or relative executable paths.
- Missing security evidence remains blocked rather than trusted.
- No raw user paths, secrets, or test artifacts are committed.
- Local `main` integration occurs only after the available gates pass; remote changes use a Draft PR rather than a direct push.

## Self-Review

- Coverage: all 37 originally observed failures were assigned to Tasks 1–5; the current full suite passes 285 of 285 tests at 75.47% command coverage.
- Scope: no dependency installation, package mutation, elevation, or unrelated refactor is planned.
- Compatibility: PowerShell 7.4+ and Pester 5.6.1 remain required; the PowerShell 7.6 structured version response is covered.
- Security: absolute process paths, PATH immutability, conservative ACL/signature checks, and artifact redaction remain explicit acceptance criteria.
