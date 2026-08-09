# Dual Publication Marker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining run-publication TOCTOU by keeping one immutable sibling guard present until a separate in-run pending marker has completed.

**Architecture:** Reuse the native `OwnedPublicationMarker` type for two independently owned handles. The sibling guard never changes path while the canonical run is unpublished; the in-run pending marker is created after the owned directory reaches its final path, moves independently during evidence quarantine, and completes before the guard is released into the run as the publication point.

**Tech Stack:** PowerShell 7, embedded C# Win32 handle wrappers, Pester 5, JSON Schema validation.

## Global Constraints

- Preserve the inventory → plan → human typed-digest approval → apply → verify boundary.
- Do not add package mutation, uninstall, elevation, source addition, dependency installation, PATH mutation, driver, firmware, reboot, or arbitrary-command behavior.
- Keep all failure evidence inside the trusted workspace `runs` directory; never delete or overwrite unknown paths.
- Use absolute `C:\Program Files\PowerShell\7\pwsh.exe` for repository commands.
- Tests and smoke checks use fixtures or `-WhatIf` only and never invoke a real package manager.
- Preserve the unrelated dirty files `src/WinPkgAgent/Private/Adapters/Scoop.ps1` and `tests/Contract/Manager.Tests.ps1` without staging or editing them.
- Legacy runs with neither publication marker remain readable.

## File structure

- `src/WinPkgAgent/Private/Workspace/RunPublication.ps1`: own, validate, quarantine, complete, and dispose the two marker handles.
- `tests/Unit/Workspace.Tests.ps1`: prove the TOCTOU interleaving, handle exclusivity, evidence failures, completion ordering, success markers, and legacy compatibility.
- `docs/superpowers/specs/2026-08-09-dual-publication-marker-design.md`: record the human-approved design status only.

---

### Task 1: Implement the immutable guard and separate pending marker

**Files:**
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1:553-678`
- Test: `tests/Unit/Workspace.Tests.ps1:490-545`

**Interfaces:**
- Consumes: `[WinPkgAgent.Native.OwnedPublicationMarker]::CreateAtomically(string path, string content)` and its `Rename`, `GetSha256`, `IsOpen`, and `Dispose` members.
- Produces: ownership properties `PublicationGuard`, `PublicationGuardPath`, `PublicationGuardHash`, `PublicationPendingMarker`, `PublicationPendingPath`, and `PublicationPendingHash`; private functions `New-WpaOwnedPublicationGuard` and `New-WpaOwnedPublicationPendingMarker`.

- [ ] **Step 1: Write the failing success and sharing tests**

Extend the existing successful publication test to require both immutable completion artifacts:

```powershell
Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeFalse
Test-Path (Join-Path $runs ".wpa-publication-guard-$($run.runId)") | Should -BeFalse
Test-Path (Join-Path $final '.wpa-publication-complete') | Should -BeTrue
Test-Path (Join-Path $final '.wpa-publication-guard-complete') | Should -BeTrue
```

Replace the single-marker ownership assertions with two real-handle assertions. Create the guard before the directory move and the pending marker after the move. For each open handle, attempt `FileMode.Open` with `FileAccess.Write` and `FileShare.ReadWrite -bor FileShare.Delete`, and attempt `[IO.File]::Delete`; both operations must throw while `GetSha256()` remains equal to the hand-derived token hash.

This test catches a regression where the publisher still moves one handle between guard and pending paths or where either marker permits replacement.

- [ ] **Step 2: Run the workspace suite and verify RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Workspace.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: FAIL because `.wpa-publication-guard-complete` is absent and the ownership object exposes only one marker handle.

- [ ] **Step 3: Split the ownership properties and constructors**

Change the ownership shape to:

```powershell
PublicationGuard = $null
PublicationGuardPath = $null
PublicationGuardHash = $null
PublicationPendingMarker = $null
PublicationPendingPath = $null
PublicationPendingHash = $null
```

Implement `New-WpaOwnedPublicationGuard` by retaining the current atomic sibling-guard creation and assigning only the three guard properties. Implement `New-WpaOwnedPublicationPendingMarker` so it validates that the guard handle remains open at the unchanged sibling path, validates the final directory is directly below `RunsPath`, atomically creates `<final>/.wpa-publication-pending` with the ownership token, and records the pending hash in `ExpectedFileHashes` and `OwnedFiles`.

Use these exact state assignments after successful creation:

```powershell
$Ownership.PublicationPendingMarker = $marker
$Ownership.PublicationPendingPath = $pendingPath
$Ownership.PublicationPendingHash = $expectedHash
$Ownership.ExpectedFileHashes.Add('.wpa-publication-pending', $expectedHash)
$Ownership.OwnedFiles.Add($pendingPath) | Out-Null
```

Do not rename the guard in either constructor.

- [ ] **Step 4: Update content validation and disposal**

For `.wpa-publication-pending`, hash through `PublicationPendingMarker.GetSha256()` while that handle is open. Dispose `PublicationPendingMarker` and `PublicationGuard` independently in `Close-WpaRunStagingOwnershipHandles`, then dispose the directory handle. Do not delete marker paths.

- [ ] **Step 5: Run the ownership-focused tests and verify GREEN for Phase A**

Run the command from Step 2.

Expected: the new ownership and sharing tests pass. Continue the same uncommitted TDD task with the next failing behavior.

---

#### Phase B: Keep the guard fixed through evidence quarantine

**Files:**
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1:778-819`
- Test: `tests/Unit/Workspace.Tests.ps1:769-841`

**Interfaces:**
- Consumes: Phase A's independent marker handles and existing handle-bound directory `Rename`.
- Produces: `Move-WpaOwnedRunToStagingEvidence` behavior that moves only the pending marker and owned directory while `PublicationGuardPath` remains continuously present.

- [ ] **Step 1: Write a deterministic failing interleaving test**

Use real files and specific fake `Rename` methods only at the filesystem transition boundary. The pending fake performs an exact file move from `<final>/.wpa-publication-pending` to the requested sibling evidence path. The directory fake's `Rename` method runs before moving the directory and calls all three consumers:

```powershell
{ Read-WpaRun $final } | Should -Throw 'RUN_PUBLICATION_PENDING'
{ Approve-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
{ Invoke-WpaRun -RunPath $final -WhatIf } | Should -Throw 'RUN_PUBLICATION_PENDING'
```

Mock `Read-WpaJsonFile`, `Approve-WpaPlan`, and `Invoke-WpaPlan` to throw if reached and assert zero invocations. After `Move-WpaOwnedRunToStagingEvidence`, assert the immutable sibling guard was present inside the directory fake callback and was never renamed. This catches the exact bug where the only marker moves from pending back to guard between a reader's two path checks.

- [ ] **Step 2: Run only the named interleaving test and verify RED**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Workspace.Tests.ps1' -DisableRegistry; `$c.Filter.FullName='*keeps the immutable guard present while pending moves to evidence*'; Invoke-Pester -Configuration `$c"
```

Expected: FAIL because the current helper renames the sole publication marker back to the guard path.

- [ ] **Step 3: Move pending to collision-safe sibling evidence without moving guard**

Before moving the directory, try at most three sibling paths named `.wpa-publication-pending-evidence-<runId>-<8 hex>`. Rename only `PublicationPendingMarker` by its retained handle and update `PublicationPendingPath`. If all three pending-marker renames fail, throw `Owned staging evidence could not be preserved.` while leaving guard and canonical directory unchanged.

Then try at most three `.staging-evidence-<runId>-<8 hex>` directory destinations using `DirectoryHandle.Rename`. After a successful directory move, rename the same pending handle into `<evidence>/.wpa-publication-pending`. If the directory or final pending-marker move fails, do not move the guard, delete files, restore paths by name, or overwrite a collision; throw the same fixed error.

- [ ] **Step 4: Add failure assertions and run the workspace suite**

Cover three pending-sibling collisions, three directory collisions after a successful pending move, and failure moving pending into the evidence directory. Every case must assert:

```powershell
Test-Path $guardPath | Should -BeTrue
Should -Invoke Remove-Item -Times 0 -Exactly
```

Run the Task 1 Step 2 command.

Expected: all evidence and consumer tests pass.

---

#### Phase C: Complete pending first and release guard last

**Files:**
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1:821-947`
- Test: `tests/Unit/Workspace.Tests.ps1:843-863` and the successful publication test near line 490

**Interfaces:**
- Consumes: both independent marker handles from Phase A and final owned-content validation.
- Produces: `Complete-WpaOwnedRunPublication -Ownership <object> -FinalPath <string>`; `.wpa-publication-guard-complete` rename is the only publication point.

- [ ] **Step 1: Write failing completion-order tests**

Add one test where pending completion throws and assert both sibling guard and in-run pending remain. Add one test where guard completion throws after pending completion and assert sibling guard plus `.wpa-publication-complete` remain while `.wpa-publication-pending` is absent. In both tests, `Read-WpaRun`, `Approve-WpaRun`, and `Invoke-WpaRun` must throw `RUN_PUBLICATION_PENDING`, and plan approval/invocation mocks must have zero calls.

These tests catch releasing the guard before pending completion and closing/removing the guard on a partial completion failure.

- [ ] **Step 2: Run the two completion tests and verify RED**

Run the workspace command from Task 1 Step 2 with `Filter.FullName` set separately to the two new exact test names.

Expected: FAIL because current completion owns only one marker and cannot preserve an independent guard.

- [ ] **Step 3: Implement ordered completion**

In `Complete-WpaOwnedRunPublication`, validate both open handles and trusted destination parents. Require both completed paths to be absent. Then execute exactly this order:

```powershell
$Ownership.PublicationPendingMarker.Rename($pendingCompletePath)
$Ownership.PublicationPendingPath = $pendingCompletePath
if ((Test-Path -LiteralPath $originalPendingPath -ErrorAction Stop) -or
    -not (Test-Path -LiteralPath $pendingCompletePath -ErrorAction Stop) -or
    -not (Test-Path -LiteralPath $Ownership.PublicationGuardPath -ErrorAction Stop)) {
    throw 'Publication pending marker completion could not be verified.'
}
$Ownership.PublicationGuard.Rename($guardCompletePath)
```

After the guard rename, verify the sibling guard and original pending paths are absent and both completed paths exist. Never attempt the guard rename if pending completion or its verification fails.

- [ ] **Step 4: Wire publication flow without an unguarded interval**

In `Publish-WpaPreparedRun`, call:

```powershell
New-WpaOwnedPublicationGuard -Ownership $ownership -RunId $runId | Out-Null
# write and validate staging
Move-WpaOwnedRunStagingDirectory -Ownership $ownership -FinalPath $finalPath
New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $finalPath | Out-Null
Assert-WpaOwnedStagingContents -Ownership $ownership -BasePath $finalPath -OwnershipReleased | Out-Null
Complete-WpaOwnedRunPublication -Ownership $ownership -FinalPath $finalPath
```

On post-rename validation failure, call the Phase B evidence helper while the guard remains fixed. On pre-rename failure, preserve staging and attempt an exact-handle guard move into that staging directory only when the canonical final path was never created; if that move fails, leave the sibling guard untouched. All outward failures remain `PREVIEW_STAGING_PRESERVED`.

- [ ] **Step 5: Run focused affected tests**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path @('./tests/Unit/Workspace.Tests.ps1','./tests/Unit/Planning.Tests.ps1','./tests/Unit/ApprovalExecution.Tests.ps1') -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: all focused tests pass, including legacy no-marker reads, manager-scope binding, and approval/invocation fail-closed paths.

- [ ] **Step 6: Commit the implementation task only**

```powershell
git add src/WinPkgAgent/Private/Workspace/RunPublication.ps1 tests/Unit/Workspace.Tests.ps1
git commit -m "fix: keep publication guard immutable"
```

Before committing, inspect `git diff --cached --name-only` and abort if either unrelated dirty Scoop file appears.

---

### Task 2: Verify and submit the bounded fix

**Files:**
- Review only: the Task 1 implementation files
- Preserve: `src/WinPkgAgent/Private/Adapters/Scoop.ps1`, `tests/Contract/Manager.Tests.ps1`

**Interfaces:**
- Consumes: the committed dual-marker implementation.
- Produces: fresh local evidence, one fresh scoped Sol review, and synchronized Plane review status.

- [ ] **Step 1: Run schema, module import, and build checks**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$ErrorActionPreference='Stop'; Get-ChildItem schemas -Filter '*.schema.json' -File | ForEach-Object { `$d=Get-Content `$_.FullName -Raw | ConvertFrom-Json; if(-not `$d.'`$schema' -or (-not `$d.type -and -not `$d.oneOf)){throw \"Invalid JSON Schema envelope: `$(`$_.Name)\"} }; Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1 -Force; Test-WpaManifest -Path ./config/packages.example.yaml | Out-Null"
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File ./scripts/build.ps1 -SkipTests
```

Expected: both commands exit 0.

- [ ] **Step 2: Run full Pester and coverage**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected current baseline: exactly three previously documented failures (empty Winget export count, empty Scoop export count, and package migration candidate `profiles: []` formatting), no new failure, and line coverage at least 75 percent. Report the exact totals from this fresh run.

- [ ] **Step 3: Run fixture-only preview WhatIf**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$w='./TestResults/dual-marker-preview-whatif'; & ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.codex.yaml -WorkspacePath `$w -WhatIf; if(`$LASTEXITCODE -ne 0){exit `$LASTEXITCODE}; if(Test-Path -LiteralPath `$w){throw 'preview WhatIf wrote artifacts'}"
```

Expected: exit 0 and no workspace path.

- [ ] **Step 4: Run analyzer only if pinned version is already available**

Check for PSScriptAnalyzer 1.25.0. If present, run it against `src` and `scripts` with `PSScriptAnalyzerSettings.psd1`; if absent, report `PSScriptAnalyzer 1.25.0 unavailable` and do not install it.

- [ ] **Step 5: Audit scope and secrets**

```powershell
git diff --check 1a33e0a..HEAD
git diff --name-only 1a33e0a..HEAD
git status --short
rg -n "approval.*bypass|force|Remove-Item|uninstall|elevat|source add|PATH" src/WinPkgAgent/Private/Workspace/RunPublication.ps1 tests/Unit/Workspace.Tests.ps1
```

Expected: only the planned spec, plan, publication source, and workspace test are committed; no deletion or approval bypass path is added; the two unrelated dirty files remain unstaged.

- [ ] **Step 6: Request exactly one fresh scoped Sol review**

Review only `1a33e0a..HEAD` against `docs/superpowers/specs/2026-08-09-dual-publication-marker-design.md`. Require findings ranked Critical/Important/Minor with file and line evidence, explicit checks of the evidence-quarantine interleaving and completion ordering, and a final PASS or FAIL. If Critical or Important remains, stop and request new human approval before any further fix wave.

- [ ] **Step 7: Submit Plane work item `WINPKGAG-2` for review**

Post one concise implementation/verification/review summary. Resolve the live REVIEW semantic; if no Review state exists, retain the nearest started-state fallback and report it. Do not move the item to Done.
