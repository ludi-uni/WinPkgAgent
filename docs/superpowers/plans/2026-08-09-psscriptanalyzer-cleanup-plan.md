# PSScriptAnalyzer Warning Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the pinned PSScriptAnalyzer 1.25.0 result from 38 warnings to zero without changing WinPkgAgent's package, approval, preflight, or atomic publication safety contracts.

**Architecture:** Apply behavior-backed fixes for real defects and private naming issues. Where analyzer heuristics conflict with deliberate public or transactional semantics, use one function-scoped `SuppressMessageAttribute` with a specific justification instead of weakening behavior or excluding a rule globally.

**Tech Stack:** PowerShell 7.4+, PSScriptAnalyzer 1.25.0, Pester 5.6.1, existing WinPkgAgent module and fixture-only CLI.

## Global Constraints

- Follow inventory, plan, approval, apply, and verify in order.
- Preserve all exported command names, parameter sets, typed-digest approval, and fail-closed reason-code behavior.
- Never install or mutate a package, add a source, elevate, reboot, invoke a driver/firmware path, alter PATH, or fall back to `powershell.exe`.
- Keep tests fixture-only and use injected process adapters.
- Do not add a global analyzer exclusion; every suppression must be function-scoped and justified.
- Keep all run artifacts inside the run directory and preserve publication ownership, reparse-point, and ACL safeguards.
- Modify only the files named by this plan unless a failing focused test proves another call site is required.

---

### Task 1: Prove stage writes honor native WhatIf

**Files:**
- Modify: `tests/Unit/Workspace.Tests.ps1`
- Modify: `src/WinPkgAgent/Private/Workspace.ps1`

**Interfaces:**
- Consumes: `Set-WpaRunStage -RunPath <string> -Stage <allowed-stage>`.
- Produces: the same private function with native `-WhatIf`; declined processing returns the validated unchanged run object and performs no `Write-WpaAtomicJson` call.

- [ ] **Step 1: Add the failing behavior test**

Add beside the existing stage-persistence test:

```powershell
It 'does not persist or report a changed stage when WhatIf declines the write' {
    $runPath = Join-Path $TestDrive 'stage-whatif-run'
    $run = [pscustomobject]@{runId='20260809-010203-aabbccdd';currentStage='planned'}
    Mock Read-WpaRun { $run }
    Mock Write-WpaAtomicJson { throw 'WRITE_GUARD' }

    $actual = Set-WpaRunStage -RunPath $runPath -Stage preflighted -WhatIf

    $actual.currentStage | Should -BeExactly 'planned'
    Should -Invoke Write-WpaAtomicJson -Times 0 -Exactly
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
Invoke-Pester -Path ./tests/Unit/Workspace.Tests.ps1 -FullNameFilter '*WhatIf declines the write*' -Output Detailed
```

Expected: FAIL because the pre-change function does not expose native `-WhatIf` behavior.

- [ ] **Step 3: Implement the minimal ShouldProcess gate**

Expand `Set-WpaRunStage` without changing its allowed stage list:

```powershell
function Set-WpaRunStage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$RunPath,
        [Parameter(Mandatory)]
        [ValidateSet('created','planned','preflighted','approved','applying','applied','verification-deferred','verified','failed')]
        [string]$Stage
    )
    $run = Read-WpaRun -RunPath $RunPath
    $runFile = Get-WpaRunArtifactPath -RunPath $RunPath -Artifact run
    if ($PSCmdlet.ShouldProcess($runFile, "Set run stage to '$Stage'")) {
        $run.currentStage = $Stage
        Write-WpaAtomicJson -Path $runFile -Data $run
    }
    return $run
}
```

- [ ] **Step 4: Run the RED test and the full Workspace unit file**

Run:

```powershell
Invoke-Pester -Path ./tests/Unit/Workspace.Tests.ps1 -Output Detailed
```

Expected: all Workspace tests pass and no real workspace or package operation is invoked.

---

### Task 2: Correct adapter and runtime analyzer findings

**Files:**
- Modify: `src/WinPkgAgent/Private/Adapters/Scoop.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Winget.ps1`
- Modify: `src/WinPkgAgent/Private/Runtime/PowerShell.ps1`
- Modify: `src/WinPkgAgent/Private/Runtime/PolicyEnvironment.ps1`
- Modify: `src/WinPkgAgent/Public/Export-WpaUnmanagedCandidate.ps1`
- Modify: `tests/Contract/Manager.Tests.ps1`
- Modify: `tests/Unit/PowerShellRuntime.Tests.ps1` only for renamed private helper references
- Modify: `tests/Unit/UnmanagedObservations.Tests.ps1`

**Interfaces:**
- Consumes: existing manager export/list fixtures and `Resolve-WpaManagerExecutable`.
- Produces: the same parsed package arrays and availability booleans; private `Get-WpaWingetUnmanagedObservation` and `Get-WpaPowerShellCandidateLabel` names replace their plural forms.

- [ ] **Step 1: Confirm existing behavior tests cover the intended mutations**

The following existing tests must fail if empty arrays become `$null` or Japanese headers stop parsing:

```powershell
Invoke-Pester -Path ./tests/Contract/Manager.Tests.ps1 -FullNameFilter '*empty winget export*','*empty scoop export*','*Japanese winget list*' -Output Detailed
```

Expected before production edits: PASS; these are characterization gates for unchanged behavior.

- [ ] **Step 2: Apply the minimal adapter fixes**

Use explicit output binding while retaining `-NoEnumerate`:

```powershell
Write-Output -InputObject ([object[]]@()) -NoEnumerate
```

Remove the unused `Executable` parameter from both private availability helpers and call them without positional arguments. Remove Winget's unused `$starts` assignments. Rename `Get-WpaWingetUnmanagedObservations` to `Get-WpaWingetUnmanagedObservation` and update production/tests call sites.

Keep the Scoop upgrade adapter signature and attach:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'Version',
    Justification='The common manager upgrade adapter contract includes Version; Scoop update does not accept it.'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'Source',
    Justification='The common manager upgrade adapter contract includes Source; Scoop update uses the installed bucket.'
)]
```

- [ ] **Step 3: Preserve Japanese parsing without a source BOM**

Replace only raw Japanese label literals with PowerShell 7 Unicode escapes, for example:

```powershell
@("`u{540D}`u{524D}", 'ID', "`u{30D0}`u{30FC}`u{30B8}`u{30E7}`u{30F3}", "`u{5229}`u{7528}`u{53EF}`u{80FD}", "`u{30BD}`u{30FC}`u{30B9}")
```

Do not change `.editorconfig` or introduce a BOM.

- [ ] **Step 4: Fix runtime fallback diagnostics and private naming**

Rename `Get-WpaPowerShellCandidateLabels` to `Get-WpaPowerShellCandidateLabel`. Replace the Authenticode empty catch with a fixed verbose message while retaining the preinitialized `signatureStatus='unavailable'` and null signer:

```powershell
catch {
    Write-Verbose 'Authenticode metadata was unavailable; the fingerprint retains unavailable signature evidence.'
}
```

- [ ] **Step 5: Run adapter, runtime, environment, and unmanaged-observation tests**

Run:

```powershell
Invoke-Pester -Path ./tests/Contract/Manager.Tests.ps1,./tests/Unit/PowerShellRuntime.Tests.ps1,./tests/Unit/Environment.Tests.ps1,./tests/Unit/UnmanagedObservations.Tests.ps1 -Output Detailed
```

Expected: all selected tests pass with fixtures only.

---

### Task 3: Rename pure/private helpers and remove dead assignments

**Files:**
- Modify: `src/WinPkgAgent/Private/Planning/PlanBuilder.ps1`
- Modify: `src/WinPkgAgent/Public/New-WpaPlan.ps1`
- Modify: `src/WinPkgAgent/Private/Workspace/RunPreparation.ps1`
- Modify: `src/WinPkgAgent/Private/Workspace.ps1`
- Modify: `src/WinPkgAgent/Private/Schema/DataFiles.ps1`
- Modify: `src/WinPkgAgent/Private/Logging/Redaction.ps1`
- Modify: `src/WinPkgAgent/Public/Invoke-WpaPlan.ps1`
- Modify: affected unit tests that invoke or mock these private helpers

**Interfaces:**
- Consumes: existing plan, schema, diagnostic, and run fixtures.
- Produces: identical objects and validation behavior under these private names: `ConvertTo-WpaPlanObject`, `Get-WpaRunPreparation`, `Test-WpaJsonTimestampElement`, `Test-WpaSchemaTimestamp`, `Get-WpaOutputDigest`, and `Read-WpaRunRecord`.

- [ ] **Step 1: Update one direct test per renamed behavior and verify RED**

Change direct private calls/mocks to the new names in their existing test files, then run:

```powershell
Invoke-Pester -Path ./tests/Unit/Planning.Tests.ps1,./tests/Unit/DiagnosticLogging.Tests.ps1,./tests/Unit/Workspace.Tests.ps1 -Output Detailed
```

Expected: FAIL with missing private command names before production functions are renamed.

- [ ] **Step 2: Rename implementations and every exact call site**

Use exact, repository-wide replacements only for the six names listed in Interfaces. `ConvertTo-WpaPlanObject` remains pure object construction; `Get-WpaRunPreparation` may read trusted inventory but writes no artifact. Do not add `ShouldProcess` to either function.

- [ ] **Step 3: Remove dead assignments without bypassing validation**

Replace unused run captures with validation-preserving calls:

```powershell
Read-WpaRun -RunPath $RunPath | Out-Null
```

Remove the unused publication `$pendingPath`, and rename the publication loop variable from automatic `$profile` to `$profileSnapshot` in all expressions in that loop.

- [ ] **Step 4: Preserve the public Preflight selector contract**

Attach a function-scoped suppression to `Invoke-WpaPlan`:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter',
    'Preflight',
    Justification='Preflight selects the parameter set; execution branches on PSCmdlet.ParameterSetName.'
)]
```

Do not remove or rename the public `Preflight` parameter.

- [ ] **Step 5: Run planning, schema, diagnostic, approval/execution, and workspace tests**

Run:

```powershell
Invoke-Pester -Path ./tests/Unit/Planning.Tests.ps1,./tests/Unit/Manifest.Tests.ps1,./tests/Unit/ResultSchema.Tests.ps1,./tests/Unit/DiagnosticLogging.Tests.ps1,./tests/Unit/ApprovalExecution.Tests.ps1,./tests/Unit/Execution.Tests.ps1,./tests/Unit/Workspace.Tests.ps1 -Output Detailed
```

Expected: all selected tests pass and exported parameter sets remain unchanged.

---

### Task 4: Clean publication helpers without splitting the atomic transaction

**Files:**
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1`
- Modify: `tests/Unit/Workspace.Tests.ps1`

**Interfaces:**
- Consumes: retained native directory/marker handles and the public `New-WpaRun` ShouldProcess gate.
- Produces: identical staging publication and fail-closed preservation behavior; private `Assert-WpaOwnedStagingContent` and `Close-WpaRunStagingOwnershipHandle` names replace plural forms.

- [ ] **Step 1: Update direct Workspace test calls to singular private names and verify RED**

Run the tests that directly create and close ownership handles after changing the calls:

```powershell
Invoke-Pester -Path ./tests/Unit/Workspace.Tests.ps1 -FullNameFilter '*ownership*','*publication*','*staging*' -Output Detailed
```

Expected: FAIL because the renamed private functions do not yet exist.

- [ ] **Step 2: Rename the private helpers, including the preservation-only removal stub**

Rename `Assert-WpaOwnedStagingContents` and `Close-WpaRunStagingOwnershipHandles` plus their exact call sites. Four safety tests directly exercise the preservation-only `Remove-WpaOwnedRunStagingDirectory`; retain that coverage under the accurate private name `Protect-WpaOwnedRunStagingDirectory`. It still performs zero deletion and always throws `PREVIEW_STAGING_PRESERVED`.

- [ ] **Step 3: Replace empty cleanup catches with bounded diagnostics**

Each best-effort `Dispose()` catch and the fallback publication-guard rename catch must contain a fixed `Write-Verbose` message. Do not include exception text, paths, tokens, or host values, and do not turn cleanup failure into deletion or a weaker outcome.

- [ ] **Step 4: Scope suppressions to the four atomic creation helpers**

Attach `PSUseShouldProcessForStateChangingFunctions` suppressions to:

```text
New-WpaOwnedDirectoryHandleAtomically
New-WpaRunStagingOwnership
New-WpaOwnedPublicationGuard
New-WpaOwnedPublicationPendingMarker
```

Each justification must state that the helper participates in the atomic transaction already gated by public `New-WpaRun`, and that an independent gate could split the transaction. Do not add nested `ShouldProcess` calls.

- [ ] **Step 5: Run the complete Workspace unit file**

Run:

```powershell
Invoke-Pester -Path ./tests/Unit/Workspace.Tests.ps1 -Output Detailed
```

Expected: all Workspace tests pass, including publication tamper/reparse/failure preservation cases.

---

### Task 5: Preserve delegated and custom WhatIf contracts with minimal suppressions

**Files:**
- Modify: `src/WinPkgAgent/Private/Workspace.ps1`
- Modify: `scripts/Private/Preview.ps1`
- Test: `tests/Unit/ApprovalExecution.Tests.ps1`
- Test: `tests/Unit/Workspace.Tests.ps1`
- Test: `tests/Integration/Cli.Tests.ps1`

**Interfaces:**
- Consumes: public `Approve-WpaRun`, public `Invoke-WpaRun`, and private `Invoke-WpaCliPreview` signatures.
- Produces: unchanged public semantics: approval delegates to `Approve-WpaPlan`; `Invoke-WpaRun -WhatIf` performs approval-free preflight and records `preflighted`; preview `-WhatIf` projects a run path and writes no workspace.

- [ ] **Step 1: Run existing contract tests before adding suppressions**

Run:

```powershell
Invoke-Pester -Path ./tests/Unit/ApprovalExecution.Tests.ps1,./tests/Unit/Workspace.Tests.ps1,./tests/Integration/Cli.Tests.ps1 -Output Detailed
```

Expected: PASS; these tests lock the behavior that analyzer-only edits must not change.

- [ ] **Step 2: Attach only the two remaining narrow suppressions**

After `Set-WpaRunStage` gains real `ShouldProcess`, rerun the analyzer. `Approve-WpaRun` no longer needs a suppression because its warning is resolved by the implementation. Use function-scoped attributes only for the two remaining rule/intent pairs:

```text
Invoke-WpaRun      -> PSUseSupportsShouldProcess: explicit WhatIf means trusted preflight, not native mutation simulation
Invoke-WpaCliPreview -> PSUseSupportsShouldProcess: wrapper forwards explicit projection-only WhatIf to New-WpaRun
```

Do not add `Force`, approval environment variables, `Confirm:$false`, or any typed-digest bypass.

- [ ] **Step 3: Re-run the same contract tests**

Expected: all selected tests pass with unchanged exports and preflight parameter sets.

---

### Task 6: Analyzer, full-suite, smoke, and commit gates

**Files:**
- Update: `.codex/tasks/psscriptanalyzer-cleanup.md`
- No production files unless a failing gate identifies an in-scope regression.

**Interfaces:**
- Consumes: all completed tasks and pinned local development modules.
- Produces: zero analyzer findings, full fixture-only verification evidence, a reviewed feature-branch diff, and Plane Review-fallback synchronization.

- [ ] **Step 1: Run the exact analyzer gate**

```powershell
Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Force
$findings = @(
    Invoke-ScriptAnalyzer -Path ./src -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
    Invoke-ScriptAnalyzer -Path ./scripts -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse
)
if ($findings.Count -gt 0) { $findings | Format-Table -AutoSize; throw "PSScriptAnalyzer found $($findings.Count) finding(s)" }
```

Expected: zero findings.

- [ ] **Step 2: Run the repository build**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File ./scripts/build.ps1
```

Expected: 285 or more tests pass, zero fail, coverage is at least 75%, and build validation completes. If managed execution blocks Pester's JUnit environment probe, rerun the identical command in the approved normal execution context and report both outcomes.

- [ ] **Step 3: Run fixture-only CLI WhatIf smoke checks**

Run only plan and preview against repository fixtures:

```powershell
$planOutput = './TestResults/analyzer-cleanup-whatif-plan.json'
$previewWorkspace = './TestResults/analyzer-cleanup-preview-whatif'
& ./scripts/winpkg-agent.ps1 plan -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.default.yaml -InventoryPath ./examples/inventory.sample.json -OutputPath $planOutput -WhatIf
if ($LASTEXITCODE -ne 0) { throw "plan WhatIf failed with exit code $LASTEXITCODE" }
if (Test-Path -LiteralPath $planOutput) { throw 'plan WhatIf wrote an artifact' }
& ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.codex.yaml -WorkspacePath $previewWorkspace -WhatIf
if ($LASTEXITCODE -ne 0) { throw "preview WhatIf failed with exit code $LASTEXITCODE" }
if (Test-Path -LiteralPath $previewWorkspace) { throw 'preview WhatIf wrote workspace artifacts' }
```

Do not invoke approve or apply.

- [ ] **Step 4: Verify compatibility and hygiene**

Compare exported functions to `WinPkgAgent.psd1`, verify `Invoke-WpaPlan` still has separate Apply and Preflight parameter sets, compare PATH before/after module import, scan the staged diff for credentials/raw host paths, and inspect `git diff --check` plus `git status --short`.

- [ ] **Step 5: Review and commit in bounded units**

Commit the approved design/plan separately from the implementation if it remains reviewable. Stage only files listed by this plan, preserve unrelated changes, and use scoped messages such as:

```text
docs: plan analyzer warning cleanup
fix: resolve powershell analyzer warnings
```

- [ ] **Step 6: Synchronize Plane without marking Done**

Post the concise implementation/verification summary to WINPKGAG-4 and leave it in the existing `In Progress` state as the documented Review fallback because the project has no Review state.

## Self-Review

- Spec coverage: all 38 baseline warnings map to Tasks 1–5; Task 6 covers every repository completion gate.
- Placeholder scan: every implementation step names exact files, functions, commands, and expected outcomes.
- Interface consistency: only private helper names change; exported functions and public parameters remain stable.
- Safety: no package mutation, approval bypass, elevation, source addition, PATH mutation, deletion path, or nested transactional confirmation is introduced.
