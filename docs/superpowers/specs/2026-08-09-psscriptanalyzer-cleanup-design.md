# PSScriptAnalyzer Warning Cleanup Design

## Objective

Make the pinned PSScriptAnalyzer 1.25.0 gate pass with zero findings while preserving WinPkgAgent's fail-closed package workflow, public command contracts, typed-digest approval, custom preflight semantics, and atomic run publication safeguards.

## Baseline

PSScriptAnalyzer 1.25.0 reports 38 warnings and no errors across `src` and `scripts`:

- 8 `PSUseShouldProcessForStateChangingFunctions`
- 8 `PSUseSingularNouns`
- 6 `PSAvoidUsingEmptyCatchBlock`
- 5 `PSReviewUnusedParameter`
- 4 `PSUseDeclaredVarsMoreThanAssignments`
- 2 `PSUseCmdletCorrectly`
- 2 `PSUseSupportsShouldProcess`
- 1 `PSAvoidAssignmentToAutomaticVariable`
- 1 `PSShouldProcess`
- 1 `PSUseBOMForUnicodeEncodedFile`

The pre-change repository baseline passes 285 of 285 Pester tests with 75.47% command coverage against the 75% threshold. Running inside the managed sandbox reaches the same test and coverage result but Pester's JUnit environment probe cannot call `Get-CimInstance`; the identical build completes under the approved normal execution context.

## Chosen approach

Use a hybrid cleanup: fix objective defects and misleading names in code, and apply narrowly scoped suppressions only where following the heuristic would change a deliberate safety contract.

### Direct fixes

- Remove dead assignments and the unused private removal stub.
- Rename the automatic `$profile` loop variable.
- Preserve empty-array output by supplying `Write-Output -InputObject` explicitly.
- Replace raw Japanese source literals with PowerShell Unicode escapes so `Winget.ps1` remains UTF-8 without BOM and continues to satisfy `.editorconfig`.
- Replace empty catches with fixed, non-sensitive verbose diagnostics or explicit fallback assignments.
- Remove ignored `Executable` parameters from private manager-availability helpers and update their callers; each helper continues to resolve the trusted absolute executable itself.
- Rename private collection helpers to approved singular nouns and update all internal/tests call sites.
- Rename object-only `New-WpaPlanObject` and read-only `New-WpaRunPreparation` to verbs matching their behavior.
- Give `Set-WpaRunStage` real `SupportsShouldProcess` behavior and prove `-WhatIf` cannot write `run.json`.

### Narrow suppressions

Every suppression is attached to one function and includes a concrete justification. No analyzer rule is disabled globally.

- Atomic publication helpers retain their `New-*` names because they create filesystem identities inside the single public `New-WpaRun` transaction. Nested `ShouldProcess` gates could partially execute that transaction.
- `Approve-WpaRun` delegates `ShouldProcess` and typed-digest behavior to `Approve-WpaPlan`; it updates the stage only after a non-WhatIf approval.
- Public `Invoke-WpaRun -WhatIf` and private CLI preview keep their existing custom meaning: trusted preflight without applying packages. Replacing them with native `SupportsShouldProcess` would change the public contract.
- `Invoke-WpaPlan -Preflight` remains an explicit parameter-set selector even though the function branches on `ParameterSetName`.
- Scoop upgrade retains `Version` and `Source` parameters so all manager adapters keep the same invocation contract; Scoop itself does not accept those values for upgrade.

## Compatibility and safety boundaries

- Exported command names and parameter sets remain unchanged.
- No package install, upgrade, uninstall, source addition, elevation, reboot, driver, firmware, or arbitrary command path is added or invoked.
- The typed-digest approval step remains human-only and cannot be bypassed.
- Unknown manager, ACL, runtime, inventory, publication, or schema state remains blocked.
- Tests use fixtures and injected process adapters only; no real package-manager mutation occurs.
- PATH is never modified, `powershell.exe` is never used as a fallback, and raw runtime paths are not persisted.

## Verification

Completion requires all of the following fresh evidence:

1. The focused stage-transition test fails before `Set-WpaRunStage` gains `ShouldProcess`, then passes after the implementation.
2. Existing manager parsing, runtime, planning, approval/execution, unmanaged-observation, diagnostic, and workspace tests pass after private renames and cleanup.
3. PSScriptAnalyzer 1.25.0 reports zero findings for both `src` and `scripts` with `PSScriptAnalyzerSettings.psd1`.
4. `scripts/build.ps1` passes all Pester tests and the 75% coverage threshold.
5. Fixture-only plan and preview `-WhatIf` smoke checks create no plan or workspace artifacts.
6. Exported commands and public parameter-set contracts remain unchanged, PATH is unchanged, and the final diff contains no secret or raw host diagnostic.
