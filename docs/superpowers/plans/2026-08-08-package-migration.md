# Existing Package Migration Candidate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate safe, reviewable management candidates from current WinGet/Scoop exports while keeping ambiguous migration and all real package changes behind human approval.

**Architecture:** Preserve the existing inventory and candidate-manifest seams. Normalize empty manager exports in the adapters, attach read-only provenance metadata to detected packages, and make the candidate exporter emit manifest-safe logical names and explicit pending-review warnings. No new package manager or mutation path is introduced.

**Tech Stack:** PowerShell 7.4+, Pester 5.x in CI, existing WinPkgAgent PowerShell module, JSON inventory schema, YAML candidate artifacts.

## Global Constraints

- Use absolute `pwsh.exe` and require PowerShell 7.4 or newer; never fall back to `powershell.exe`.
- Never install dependencies automatically.
- Never uninstall, elevate, reboot, add sources, modify drivers/BIOS/firmware, or execute arbitrary commands.
- Inventory and candidate generation must remain read-only with respect to package state.
- Preserve unrelated user changes and do not store raw manager executable paths in artifacts.
- Candidate artifacts remain `reviewStatus: pending` until a human confirms source, category, ownership, and migration impact.

---

### Task 1: Lock manager export behavior with failing tests

**Files:**
- Modify: `tests/Contract/Manager.Tests.ps1`
- Create: `tests/Unit/PackageMigration.Tests.ps1`

**Interfaces:**
- Tests consume `ConvertFrom-WpaWingetExport`, `ConvertFrom-WpaScoopExport`, and `Export-WpaManifestCandidate` through the module's in-module test scope.
- Tests require empty exports to return an empty array and candidate output to use a manifest-safe logical name.

- [ ] **Step 1: Add the failing empty-export tests**

Add contract assertions for `{ "Sources": [] }` and `{ "apps": [] }` to return an empty result rather than `$null`.

- [ ] **Step 2: Add the failing candidate test**

Create an inventory fixture object containing `displayName = 'Notepad++.Notepad++'`, manager `winget`, id `Notepad++.Notepad++`, version `8.9.6.4`, and source `$null`. Mock only file/schema boundaries, write the candidate to `$TestDrive`, and assert that the candidate contains `reviewStatus: pending`, `profiles: []`, a lowercase manifest-safe name, and the installed version.

- [ ] **Step 3: Run the focused tests with PowerShell 7**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Set-Location -LiteralPath '$PWD'; Invoke-Pester -Path ./tests/Contract/Manager.Tests.ps1,./tests/Unit/PackageMigration.Tests.ps1 -Output Detailed"
```

Expected: the new tests fail because empty exports are currently treated as malformed and candidate names are taken from a missing `name` property.

### Task 2: Normalize exports and candidate names

**Files:**
- Modify: `src/WinPkgAgent/Private/Adapters/Scoop.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Winget.ps1`
- Modify: `src/WinPkgAgent/Public/Export-WpaManifestCandidate.ps1`
- Modify: `src/WinPkgAgent/WinPkgAgent.psm1` only if a new helper must be exported; private helpers should remain private.

**Interfaces:**
- `ConvertFrom-WpaScoopExport` and `ConvertFrom-WpaWingetExport` return `@()` for valid empty exports.
- Candidate export accepts the existing inventory path and output path without changing its public parameters.

- [ ] **Step 1: Implement empty-export normalization**

Distinguish a missing property or malformed object from an explicitly empty `apps`/`Packages` collection. Keep malformed JSON as `$null` so the existing fail-closed status remains intact.

- [ ] **Step 2: Add provenance metadata**

Set package metadata to identify the read-only detection source (`winget-export` or `scoop-export`) without persisting executable paths or raw diagnostics.

- [ ] **Step 3: Implement deterministic logical names**

Derive the candidate logical name from the manager package ID, lowercase it, replace unsupported characters with `-`, prefix if the first character is invalid, and cap the result at the manifest limit. Resolve collisions deterministically in sorted manager/id order.

- [ ] **Step 4: Emit explicit pending candidate structure**

Include `profiles: []`, retain `reviewStatus: pending`, preserve known source/version, and add a warning that export detection does not prove original manager ownership. Do not invent a source or category when the inventory lacks one.

### Task 3: Run green focused verification and real read-only smoke checks

**Files:**
- Modify: `docs/usage.ja.md` and `docs/package-ownership.md` only if the final behavior needs documentation clarification.

**Interfaces:**
- No public mutation interface changes.

- [ ] **Step 1: Run focused tests under PowerShell 7**

Run the same focused Pester command from Task 1 using the repository's supported Pester 5.x environment. If only Pester 3.x is installed locally, report that limitation and use direct PowerShell 7 assertion scripts for the changed functions without installing dependencies.

- [ ] **Step 2: Run repository schema and changed-surface tests**

Run the manifest, inventory, manager contract, and planning tests under PowerShell 7.

- [ ] **Step 3: Run the real read-only inventory under the user's PowerShell 7 context**

Write the inventory and pending candidate only under the worktree's local artifact directory. Confirm manager status, package count, and that no mutation adapter was invoked.

- [ ] **Step 4: Review diff and safety boundaries**

Confirm no uninstall/elevation/source-addition/arbitrary-command path was added, no raw executable path was written to artifacts, and the unrelated main-worktree file remains untouched.

### Task 4: Prepare the approval boundary

**Files:**
- Create: worktree-local review artifacts under `artifacts/` only; do not promote them to the active manifest.

- [ ] **Step 1: Generate the candidate manifest**

Use the real inventory artifact with `Export-WpaManifestCandidate`. Leave `reviewStatus: pending`.

- [ ] **Step 2: Stop before approval or package mutation**

Report the artifact paths, candidate counts, manager failures/warnings, and the exact human decisions still required. Do not call `Approve-WpaPlan` or `Invoke-WpaPlan`.
