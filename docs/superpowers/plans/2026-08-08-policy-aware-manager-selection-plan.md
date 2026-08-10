# Policy-aware Manager Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the caller to select an explicit policy file so inventory, planning, apply, verification, and resume use only the managers permitted by that policy.

**Architecture:** Add a policy-scoped manager list at the inventory boundary. Get-WpaInventory -PolicyPath validates the policy, calculates its hash, and invokes only the allowed adapters; the resulting inventory records schema version 2, policy hash, and manager scope. Plan evaluation checks allowedManagers before fingerprint requirements, while apply, verify, run, and resume pass the same policy path through every re-inventory call.

**Tech Stack:** PowerShell 7.4+, powershell-yaml 0.4.12, Pester 5.x, JSON Schema, existing ProcessStartInfo manager adapters, existing atomic artifact writers.

## Global Constraints

- Use explicit policy files; do not add policy inheritance, overlay, or automatic Codex/desktop detection.
- Only managers listed in policy.allowedManagers may be probed or invoked by a policy-scoped workflow.
- A policy-disallowed package becomes blocked / MANAGER_NOT_ALLOWED; it is never remapped to another manager automatically.
- Existing approval, policy hash, inventory hash, manager fingerprint, -WhatIf, preflight, and fail-closed boundaries remain mandatory.
- Do not change PATH, execution policy, App Installer settings, OS policy, privilege level, or sandbox restrictions.
- Do not add uninstall, elevation, reboot, driver, firmware, arbitrary-command, or real-package test paths.
- Runtime dependency remains powershell-yaml 0.4.12; development dependencies are installed explicitly by CI or the developer.
- Preserve the user’s existing unrelated changes in docs/usage.md, docs/usage.ja.md, and docs/superpowers/plans/2026-08-05-test-suite-stabilization.md.
- Keep manager executable paths in memory only; artifacts contain hashes and metadata, never raw resolved paths.

---

## File Map

### Policy contract and samples

- Create: config/policy.codex.yaml — Scoop-only policy for Codex or another environment where WinGet is unavailable.
- Create: config/policy.desktop.yaml — explicit WinGet+Scoop desktop policy.
- Modify: config/policy.default.yaml — retain the current desktop-compatible policy as the compatibility default.
- Modify: schemas/policy.schema.json — require at least one allowed manager.
- Modify: src/WinPkgAgent/Private/Core/Validation.ps1 — enforce non-empty allowed managers at the runtime boundary.
- Test: tests/Unit/Manifest.Tests.ps1 — reject empty manager scopes and validate the policy samples.

### Policy-scoped inventory

- Modify: schemas/inventory.schema.json — move to schema version 2 and add policyHash and managerScope.
- Modify: src/WinPkgAgent/Private/Inventory/Aggregator.ps1 — aggregate only an explicit manager list and compute success relative to that list.
- Modify: src/WinPkgAgent/Public/Get-WpaInventory.ps1 — require -PolicyPath, validate the policy, and pass the selected scope to the aggregator.
- Modify: src/WinPkgAgent/Private/Core/Canonical.ps1 — include inventory policy scope in the inventory state hash.
- Test: tests/Unit/Inventory.Tests.ps1 — prove disallowed adapters are not called and one-manager success is not incorrectly reported as partial.
- Test: tests/Unit/Manifest.Tests.ps1 — validate inventory schema v2 fixtures.
- Modify: examples/inventory.sample.json — add schema v2 provenance fields.

### Environment and CLI propagation

- Modify: src/WinPkgAgent/Public/Test-WpaEnvironment.ps1 — probe only policy-allowed managers when -PolicyPath is supplied and compute readiness against the selected scope.
- Modify: scripts/winpkg-agent.ps1 — pass -PolicyPath through environment, inventory, and resume-verify.
- Test: tests/Unit/Environment.Tests.ps1 — prove readiness uses the selected scope and does not probe excluded managers.
- Test: tests/Integration/Cli.Tests.ps1 — prove the command surface accepts and propagates the policy path.

### Planning and execution propagation

- Modify: src/WinPkgAgent/Private/Planning/Evaluation.ps1 — evaluate MANAGER_NOT_ALLOWED before manager availability and fingerprint checks.
- Modify: src/WinPkgAgent/Public/New-WpaPlan.ps1 — validate inventory policy hash/scope and skip fingerprint requirements for policy-disallowed packages.
- Modify: src/WinPkgAgent/Public/Invoke-WpaPlan.ps1 — pass the same policy path to current and after-apply inventory calls.
- Modify: src/WinPkgAgent/Public/Resume-WpaVerification.ps1 — accept and pass -PolicyPath to the resume inventory call.
- Modify: src/WinPkgAgent/Private/Workspace.ps1 — pass the copied run policy to New-WpaRun inventory creation and resume paths.
- Test: tests/Unit/Planning.Tests.ps1 — cover reason ordering, policy hash mismatch, and inventory scope mismatch.
- Test: tests/Unit/Execution.Tests.ps1, tests/Unit/ApprovalExecution.Tests.ps1, and tests/Unit/Workspace.Tests.ps1 — cover policy propagation without mutation or approval bypass.

### Documentation

- Modify: README.md, README.ja.md — document explicit Codex/desktop policy selection and the no-bypass boundary.
- Modify: docs/usage.md, docs/usage.ja.md — add policy-aware inventory commands and migration guidance while preserving existing user edits.
- Modify: docs/architecture.md, docs/architecture.ja.md — describe policy scope as an inventory boundary and schema v2 provenance fields.
- Modify: docs/troubleshooting.md — distinguish policy-disallowed, manager-unavailable, and Codex visibility failures.
- Modify: CHANGELOG.md — record explicit policy selection and the inventory schema migration.

---

## Task 1: Add the policy contract and environment policy samples

**Files:**
- Create: config/policy.codex.yaml
- Create: config/policy.desktop.yaml
- Modify: schemas/policy.schema.json
- Modify: src/WinPkgAgent/Private/Core/Validation.ps1
- Test: tests/Unit/Manifest.Tests.ps1

**Interfaces:**
- Consumes: Existing policy object with allowedManagers.
- Produces: A policy contract that rejects an empty manager scope and two valid explicit policy files.

- [ ] Step 1: Write the failing tests. Add tests that make an empty allowedManagers policy fail JSON Schema validation and Test-WpaPolicyObject, and that parse both sample files through the existing policy validation path.

~~~powershell
It 'rejects an empty allowed manager scope' {
    $policy = [ordered]@{
        schemaVersion=1; allowInstall=$true; allowUpgrade=@('patch')
        allowedManagers=@(); allowedSources=@('main'); protectedPackages=@()
        dangerousCategories=@('driver','bios','uefi','firmware'); allowUninstall=$false
        requireApproval=$true; approvalValidityMinutes=30; rejectStateChanges=$true
        maxOperations=10; operationTimeoutSeconds=60; rebootHandling='record-only'
        unknownVersionHandling='block'
    }
    { Test-WpaPolicyObject ([pscustomobject]$policy) } | Should -Throw '*manager*'
}
~~~

- [ ] Step 2: Run the focused test to verify it fails.

Run: Invoke-Pester -Path ./tests/Unit/Manifest.Tests.ps1 -Output Detailed

Expected: the new empty-scope test fails because the current schema/runtime validation accepts an empty array.

- [ ] Step 3: Implement the minimal contract change. Add minItems: 1 to allowedManagers in schemas/policy.schema.json and add the matching fail-closed runtime check in Test-WpaPolicyObject. Create policy.codex.yaml with allowedManagers: [scoop] and only Scoop sources; create policy.desktop.yaml with allowedManagers: [winget, scoop] and the current desktop settings. Do not relax any existing safety constants.

- [ ] Step 4: Run focused tests and sample validation.

Run: Invoke-Pester -Path ./tests/Unit/Manifest.Tests.ps1 -Output Detailed

Expected: PASS, including policy sample validation and empty-scope rejection.

- [ ] Step 5: Commit the task.

~~~powershell
git add schemas/policy.schema.json src/WinPkgAgent/Private/Core/Validation.ps1 config/policy.codex.yaml config/policy.desktop.yaml tests/Unit/Manifest.Tests.ps1
git commit -m "feat: add explicit manager policy samples"
~~~

## Task 2: Make inventory policy-scoped and add schema v2 provenance

**Files:**
- Modify: schemas/inventory.schema.json
- Modify: src/WinPkgAgent/Private/Inventory/Aggregator.ps1
- Modify: src/WinPkgAgent/Public/Get-WpaInventory.ps1
- Modify: src/WinPkgAgent/Private/Core/Canonical.ps1
- Test: tests/Unit/Inventory.Tests.ps1
- Test: tests/Unit/Manifest.Tests.ps1
- Modify: examples/inventory.sample.json

**Interfaces:**
- Consumes: Get-WpaInventoryAggregate -Adapters hashtable -Managers string[] -PolicyHash string.
- Produces: An inventory object with schemaVersion=2, policyHash, managerScope, only selected manager records, and status calculated over the selected scope.

- [ ] Step 1: Write the failing scoped-inventory tests. Add a Pester test that supplies a throwing WinGet adapter and a successful Scoop adapter while selecting only Scoop. Assert that WinGet is not called, the manager list contains only Scoop, managerScope is @('scoop'), and status is success. Add a second test proving a selected manager failure is failed when it is the only selected manager.

~~~powershell
It 'does not call excluded managers and succeeds for a healthy single-manager scope' {
    InModuleScope WinPkgAgent {
        $script:wingetCalls = 0
        $r = Get-WpaInventoryAggregate -Managers @('scoop') -PolicyHash ('a' * 64) -Adapters @{
            winget = { $script:wingetCalls++; throw 'excluded manager called' }
            scoop = { [pscustomobject]@{Success=$true; Packages=@(); Warning=$null} }
        }
        $script:wingetCalls | Should -Be 0
        $r.status | Should -Be 'success'
        @($r.managers.manager) | Should -Be @('scoop')
        @($r.managerScope) | Should -Be @('scoop')
    }
}
~~~

- [ ] Step 2: Run the focused test to verify it fails.

Run: Invoke-Pester -Path ./tests/Unit/Inventory.Tests.ps1 -Output Detailed

Expected: FAIL because the aggregator currently loops over both fixed manager names and returns schema version 1 without scope fields.

- [ ] Step 3: Implement the scoped aggregator and public boundary. Add the manager list and policy hash parameters, normalize and sort the selected list, call only selected adapters, and calculate success when every selected manager succeeds. Make Get-WpaInventory -PolicyPath read and validate the policy, calculate Get-WpaObjectHash $policy, and pass allowedManagers to the aggregator. Emit schema version 2, policyHash, and managerScope.

- [ ] Step 4: Update canonical inventory hashing and schema fixtures. Include policyHash and sorted managerScope in Get-WpaInventoryStateHash. Update schemas/inventory.schema.json and examples/inventory.sample.json so schema v2 requires the two provenance fields. Update fixture-based schema tests without changing package semantics.

- [ ] Step 5: Run focused inventory and schema tests.

Run: Invoke-Pester -Path ./tests/Unit/Inventory.Tests.ps1,./tests/Unit/Manifest.Tests.ps1 -Output Detailed

Expected: PASS; no test invokes a real manager.

- [ ] Step 6: Commit the task.

~~~powershell
git add schemas/inventory.schema.json src/WinPkgAgent/Private/Inventory/Aggregator.ps1 src/WinPkgAgent/Public/Get-WpaInventory.ps1 src/WinPkgAgent/Private/Core/Canonical.ps1 tests/Unit/Inventory.Tests.ps1 tests/Unit/Manifest.Tests.ps1 examples/inventory.sample.json
git commit -m "feat: scope inventory to selected policy managers"
~~~

## Task 3: Apply the selected scope to environment checks and CLI entry points

**Files:**
- Modify: src/WinPkgAgent/Public/Test-WpaEnvironment.ps1
- Modify: scripts/winpkg-agent.ps1
- Test: tests/Unit/Environment.Tests.ps1
- Test: tests/Integration/Cli.Tests.ps1

**Interfaces:**
- Consumes: Test-WpaEnvironment -PolicyPath path and the policy-scoped inventory API.
- Produces: Read-only environment output whose readiness is computed over allowed managers, plus CLI propagation for environment, inventory, and resume-verify.

- [ ] Step 1: Write failing environment tests. Mock Test-WpaWingetAvailable and Test-WpaScoopAvailable, load policy.codex.yaml, and assert that readiness depends on Scoop while excluded WinGet is not probed. Add a desktop-policy test where WinGet is unavailable and readiness is false.

- [ ] Step 2: Run the focused tests to verify failure.

Run: Invoke-Pester -Path ./tests/Unit/Environment.Tests.ps1 -Output Detailed

Expected: FAIL because Test-WpaEnvironment currently probes both managers and defines readiness as “any manager available.”

- [ ] Step 3: Implement policy-aware environment probing. Read and validate the policy when -PolicyPath is provided, invoke availability checks only for allowedManagers, preserve the existing PowerShell/YAML checks, and define ready as compatible PowerShell plus all allowed managers available. Keep excluded managers unattempted rather than treating them as failures.

- [ ] Step 4: Propagate -PolicyPath in the CLI. Pass the parameter into the inventory branch and add it to the resume-verify branch. Keep plan, invoke, and new-run parameter behavior intact while ensuring the inventory command cannot omit its policy path.

- [ ] Step 5: Run focused environment and CLI tests.

Run: Invoke-Pester -Path ./tests/Unit/Environment.Tests.ps1,./tests/Integration/Cli.Tests.ps1 -Output Detailed

Expected: PASS, with no live manager calls.

- [ ] Step 6: Commit the task.

~~~powershell
git add src/WinPkgAgent/Public/Test-WpaEnvironment.ps1 scripts/winpkg-agent.ps1 tests/Unit/Environment.Tests.ps1 tests/Integration/Cli.Tests.ps1
git commit -m "feat: propagate policy scope through environment CLI"
~~~

## Task 4: Make planning policy-first and reject mismatched inventory scope

**Files:**
- Modify: src/WinPkgAgent/Private/Planning/Evaluation.ps1
- Modify: src/WinPkgAgent/Public/New-WpaPlan.ps1
- Test: tests/Unit/Planning.Tests.ps1

**Interfaces:**
- Consumes: schema v2 inventory with policyHash and managerScope.
- Produces: MANAGER_NOT_ALLOWED blocked actions before fingerprint lookup, and INVENTORY_SCOPE_MISMATCH fail-closed validation for allowed managers absent from the inventory scope.

- [ ] Step 1: Write failing planning tests. Add one pure evaluation test with a Scoop-only policy, a WinGet manifest package, and no WinGet manager record. Assert the result is blocked with MANAGER_NOT_ALLOWED. Add a New-WpaPlan test where policy and inventory policyHash differ and assert INVENTORY_SCOPE_MISMATCH before any mutation or approval path.

~~~powershell
It 'blocks a package before fingerprint lookup when its manager is disallowed' {
    $policy.allowedManagers = @('scoop')
    $manifest = [pscustomobject]@{ packages=@([pscustomobject]@{
        name='vscode'; manager='winget'; id='Microsoft.VisualStudioCode'
        state='present'; version='latest'; source='winget'
    }) }
    $inventory = [pscustomobject]@{ status='success'; managers=@(); packages=@() }
    $result = Get-WpaPlanEvaluation -Manifest $manifest -Policy $policy -Inventory $inventory
    $result.actions[0].classification | Should -Be 'blocked'
    $result.actions[0].reasonCode | Should -Be 'MANAGER_NOT_ALLOWED'
}
~~~

- [ ] Step 2: Run the focused tests to verify failure.

Run: Invoke-Pester -Path ./tests/Unit/Planning.Tests.ps1 -Output Detailed

Expected: FAIL because evaluation currently checks inventory status before policy allowance and plan creation expects fingerprints for every declared manager.

- [ ] Step 3: Implement policy-first evaluation. Move the allowedManagers check ahead of manager state and fingerprint assumptions. For disallowed packages, emit a blocked action with no operation. For allowed packages, require the manager to exist in managerScope and have a successful manager record; when the inventory scope omits an allowed declared manager, throw the stable INVENTORY_SCOPE_MISMATCH error at the artifact boundary.

- [ ] Step 4: Implement plan/inventory binding. In New-WpaPlan, validate inventory schema v2, compare inventory policyHash with the loaded policy hash, and ensure every manager required by an allowed manifest package is in managerScope. Skip fingerprint prechecks for packages already disallowed by policy. Keep plan policyHash and inventoryHash generation unchanged except for the schema v2 inventory contents.

- [ ] Step 5: Run planning tests and fixture-only plan generation.

Run: Invoke-Pester -Path ./tests/Unit/Planning.Tests.ps1 -Output Detailed

Expected: PASS, including existing upgrade/source/protected-package behavior and the new policy-first cases.

- [ ] Step 6: Commit the task.

~~~powershell
git add src/WinPkgAgent/Private/Planning/Evaluation.ps1 src/WinPkgAgent/Public/New-WpaPlan.ps1 tests/Unit/Planning.Tests.ps1
git commit -m "feat: evaluate manager policy before planning fingerprints"
~~~

## Task 5: Propagate policy through apply, verification, runs, and resume

**Files:**
- Modify: src/WinPkgAgent/Public/Invoke-WpaPlan.ps1
- Modify: src/WinPkgAgent/Public/Resume-WpaVerification.ps1
- Modify: src/WinPkgAgent/Private/Workspace.ps1
- Modify: scripts/winpkg-agent.ps1
- Test: tests/Unit/Execution.Tests.ps1
- Test: tests/Unit/ApprovalExecution.Tests.ps1
- Test: tests/Unit/Workspace.Tests.ps1

**Interfaces:**
- Consumes: -PolicyPath already required by plan/apply and the run’s copied policy.yaml.
- Produces: Every re-inventory call uses the same policy scope as the plan; resume requires an explicit policy path outside a run.

- [ ] Step 1: Write failing propagation tests. Mock Get-WpaInventory with a parameter-aware mock that records -PolicyPath. Exercise preflight/apply and assert the current and after-apply inventory calls receive the supplied path. Add a workspace test asserting New-WpaRun passes the copied policy path to its initial inventory. Add a resume test asserting Resume-WpaVerification -PolicyPath uses the same path.

- [ ] Step 2: Run focused tests to verify failure.

Run: Invoke-Pester -Path ./tests/Unit/Execution.Tests.ps1,./tests/Unit/ApprovalExecution.Tests.ps1,./tests/Unit/Workspace.Tests.ps1 -Output Detailed

Expected: FAIL because current inventory calls omit -PolicyPath and Resume-WpaVerification has no policy parameter.

- [ ] Step 3: Implement propagation without changing mutation gates. Pass $PolicyPath into current and after-apply Get-WpaInventory calls. Add the explicit policy parameter to resume and pass the run-local policy path from Invoke-WpaRun. Update New-WpaRun to call Get-WpaInventory -PolicyPath using its copied policy file. Do not alter approval validation, journal handling, ShouldProcess, operation sequencing, or verification reason codes.

- [ ] Step 4: Update the CLI resume branch. Forward the top-level -PolicyPath to Resume-WpaVerification; preserve existing exit-code behavior.

- [ ] Step 5: Run focused execution/workspace tests.

Run: Invoke-Pester -Path ./tests/Unit/Execution.Tests.ps1,./tests/Unit/ApprovalExecution.Tests.ps1,./tests/Unit/Workspace.Tests.ps1 -Output Detailed

Expected: PASS, with existing tests still proving approval and mutation adapters are not bypassed.

- [ ] Step 6: Commit the task.

~~~powershell
git add src/WinPkgAgent/Public/Invoke-WpaPlan.ps1 src/WinPkgAgent/Public/Resume-WpaVerification.ps1 src/WinPkgAgent/Private/Workspace.ps1 scripts/winpkg-agent.ps1 tests/Unit/Execution.Tests.ps1 tests/Unit/ApprovalExecution.Tests.ps1 tests/Unit/Workspace.Tests.ps1
git commit -m "feat: preserve policy scope through execution and resume"
~~~

## Task 6: Update documentation and migration guidance

**Files:**
- Modify: README.md
- Modify: README.ja.md
- Modify: docs/usage.md
- Modify: docs/usage.ja.md
- Modify: docs/architecture.md
- Modify: docs/architecture.ja.md
- Modify: docs/troubleshooting.md
- Modify: CHANGELOG.md
- Test: tests/Integration/Cli.Tests.ps1

**Interfaces:**
- Consumes: Completed policy-aware CLI and schema v2 behavior.
- Produces: Copyable commands that explicitly select policy.codex.yaml or policy.desktop.yaml, plus honest migration/error guidance.

- [ ] Step 1: Add documentation/sample assertions first. Extend the existing CLI/sample test to assert the documented policy-scoped inventory command includes -PolicyPath and that the sample inventory validates against schema v2.

- [ ] Step 2: Run the focused documentation/sample test to verify failure.

Run: Invoke-Pester -Path ./tests/Integration/Cli.Tests.ps1 -Output Detailed

Expected: FAIL until the sample artifact and command assertions match the new policy-bound flow.

- [ ] Step 3: Update docs without overwriting unrelated user edits. Document explicit policy selection, the no-bypass boundary, blocked WinGet packages under Codex policy, inventory regeneration for old artifacts, and the distinction between MANAGER_NOT_ALLOWED, MANAGER_UNAVAILABLE, and INVENTORY_SCOPE_MISMATCH.

- [ ] Step 4: Run docs/sample checks.

Run: Invoke-Pester -Path ./tests/Integration/Cli.Tests.ps1 -Output Detailed

Expected: PASS, with no real manager invocation.

- [ ] Step 5: Commit the task.

~~~powershell
git add README.md README.ja.md docs/usage.md docs/usage.ja.md docs/architecture.md docs/architecture.ja.md docs/troubleshooting.md CHANGELOG.md examples/inventory.sample.json tests/Integration/Cli.Tests.ps1
git commit -m "docs: document explicit manager policy selection"
~~~

## Task 7: Run repository verification and review the diff

**Files:**
- Test: All affected Pester suites under tests/Unit and tests/Integration.
- Verify: scripts/build.ps1, scripts/winpkg-agent.ps1, schema files, and Git diff.

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: Fresh evidence that the policy-scoped workflow is schema-valid, fixture-only, lint-clean, and free of approval bypass or real package mutation.

- [ ] Step 1: Run closest affected tests in order.

~~~powershell
Invoke-Pester -Path ./tests/Unit/Manifest.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests/Unit/Inventory.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests/Unit/Planning.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests/Unit/Environment.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests/Unit/Execution.Tests.ps1,./tests/Unit/ApprovalExecution.Tests.ps1,./tests/Unit/Workspace.Tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests/Integration/Cli.Tests.ps1 -Output Detailed
~~~

Expected: PASS for every affected suite. If a suite is kept in an existing file instead of a new file, omit only that nonexistent path and report the exact command adjustment.

- [ ] Step 2: Run the repository-configured Pester suite.

Run: . ./tests/PesterConfiguration.ps1; $config=Get-WpaPesterConfiguration -Path './tests'; Invoke-Pester -Configuration $config

Expected: PASS with the repository’s configured output.

- [ ] Step 3: Run schema, analyzer, build, and fixture-only smoke checks.

~~~powershell
./scripts/build.ps1
Invoke-ScriptAnalyzer -Path ./src -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
Invoke-ScriptAnalyzer -Path ./scripts -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
./scripts/winpkg-agent.ps1 plan -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.default.yaml -InventoryPath ./examples/inventory.sample.json -OutputPath ./TestResults/whatif-policy-plan.json -WhatIf
~~~

Expected: all checks pass; the CLI smoke test is fixture-only and does not invoke a real manager mutation.

- [ ] Step 4: Review security and compatibility boundaries. Confirm no code calls excluded adapters, no fallback changes package ownership, no PATH/policy/elevation operation was added, and no test points to a real package manager. Confirm inventory schema v1 artifacts are rejected or regenerated as designed.

- [ ] Step 5: Review the final diff and status.

~~~powershell
git diff --check
git diff HEAD~6..HEAD --stat
git status --short
~~~

Expected: only intended policy-selection files and pre-existing unrelated working-tree changes remain. Do not stage or revert unrelated changes.

- [ ] Step 6: Commit only verification fixes if they are necessary. If all checks pass, leave the tree unchanged. If a check exposes a defect, stage only the exact affected file path and commit with a message that names the verified defect and fix; never stage the unrelated pre-existing documentation or plan changes.

## Completion Criteria

- policy.codex.yaml selects Scoop without probing WinGet.
- policy.desktop.yaml or policy.default.yaml selects WinGet and Scoop.
- Policy-scoped inventory records policyHash and managerScope in schema v2.
- Disallowed manifest managers are blocked with MANAGER_NOT_ALLOWED before fingerprint lookup.
- Apply, after-apply verification, run creation, and reboot resume use the same policy scope.
- Existing human approval, hash revalidation, no-bypass, and fixture-only test boundaries remain intact.
- Focused Pester, full Pester, PSScriptAnalyzer, build/schema, and fixture-only CLI checks have fresh passing evidence.
- No unrelated user changes are staged, committed, reverted, or reformatted.
