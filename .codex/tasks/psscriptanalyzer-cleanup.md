# PSScriptAnalyzer cleanup task state

## Objective

Resolve all 38 PSScriptAnalyzer 1.25.0 warnings without weakening WinPkgAgent safety or changing exported command contracts.

## Scope

### Included

- Direct cleanup of dead assignments, automatic-variable use, empty catches, empty-array output, and ASCII-safe Winget locale labels.
- Private helper renames for singular nouns and accurate non-mutating verbs.
- Native `ShouldProcess` for the private run-stage writer.
- Function-scoped, justified suppressions where analyzer heuristics conflict with deliberate public/preflight/atomic adapter contracts.
- Focused and full fixture-only verification.

### Excluded

- Package installation, upgrade, uninstall, source changes, elevation, reboot, drivers, firmware, or arbitrary commands.
- Changes to typed-digest approval, exported command names, public parameter sets, policy schema, run schema, or reason codes.
- Dependency updates, global analyzer exclusions, broad formatting, and unrelated refactors.
- Push, merge, auto-merge, release, or deployment.

## Decisions

- Human approved the hybrid direct-fix plus narrow-suppression design.
- Plane work item: WINPKGAG-4, currently In Progress.
- Branch: `codex/winpkgag-4-psscriptanalyzer-cleanup` in an isolated worktree.
- Atomic publication helpers remain under the single public `New-WpaRun` gate; no nested `ShouldProcess` gates.
- Public `Invoke-WpaRun -WhatIf` remains trusted preflight, not native WhatIf simulation.
- Winget raw Japanese labels become PowerShell Unicode escapes rather than adding a BOM that conflicts with `.editorconfig`.
- Four tests directly referenced the preservation-only removal stub; it remains as `Protect-WpaOwnedRunStagingDirectory`, still performs zero deletion, and retains those safety tests.
- Real `ShouldProcess` support in `Set-WpaRunStage` removed the `Approve-WpaRun` warning, so no stale suppression was added there.

## Files

### Read

- `PSScriptAnalyzerSettings.psd1`
- `.editorconfig`
- `.github/workflows/ci.yml`
- `scripts/build.ps1`
- Analyzer-affected source/scripts and their focused tests.

### Changed

- `docs/superpowers/specs/2026-08-09-psscriptanalyzer-cleanup-design.md`
- `docs/superpowers/plans/2026-08-09-psscriptanalyzer-cleanup-plan.md`
- `.codex/tasks/psscriptanalyzer-cleanup.md`
- `scripts/Private/Preview.ps1`
- `src/WinPkgAgent/Private/Adapters/Scoop.ps1`
- `src/WinPkgAgent/Private/Adapters/Winget.ps1`
- `src/WinPkgAgent/Private/Logging/Redaction.ps1`
- `src/WinPkgAgent/Private/Planning/PlanBuilder.ps1`
- `src/WinPkgAgent/Private/Runtime/PowerShell.ps1`
- `src/WinPkgAgent/Private/Schema/DataFiles.ps1`
- `src/WinPkgAgent/Private/Workspace.ps1`
- `src/WinPkgAgent/Private/Workspace/RunPreparation.ps1`
- `src/WinPkgAgent/Private/Workspace/RunPublication.ps1`
- `src/WinPkgAgent/Public/Export-WpaUnmanagedCandidate.ps1`
- `src/WinPkgAgent/Public/Invoke-WpaPlan.ps1`
- `src/WinPkgAgent/Public/New-WpaPlan.ps1`
- `tests/Unit/DiagnosticLogging.Tests.ps1`
- `tests/Unit/Planning.Tests.ps1`
- `tests/Unit/UnmanagedObservations.Tests.ps1`
- `tests/Unit/Workspace.Tests.ps1`

## Acceptance criteria

- [x] PSScriptAnalyzer 1.25.0 reports zero findings for `src` and `scripts`.
- [x] A RED test proves `Set-WpaRunStage -WhatIf` did not previously protect the write; the implementation makes it GREEN.
- [x] Exported command names and Apply/Preflight parameter sets are unchanged.
- [x] Focused affected tests pass using fixtures/injected adapters only.
- [x] Full build passes with at least 285 tests, zero failures, and at least 75% command coverage.
- [x] Fixture-only plan/preview WhatIf writes no plan or workspace artifact.
- [x] PATH is unchanged and the diff contains no secret or raw host diagnostic.
- [x] Only approved files are committed on the feature branch.
- [x] WINPKGAG-4 received verification and remains In Progress as the Review fallback rather than Done.

## Tests

- [x] Pre-change build under approved normal execution: 285/285 passed; 75.47% coverage; build completed.
- [x] Pre-change managed build: tests and coverage passed; JUnit export alone was blocked by `Get-CimInstance` access denial.
- [x] Focused stage test: RED before implementation, GREEN after implementation.
- [x] Publication rename tests: 7 expected RED failures, then Workspace 66/66 GREEN.
- [x] Affected contract groups: 87/87 before and after the two suppressions.
- [x] Exact PSScriptAnalyzer 1.25.0 gate: 0 findings with repository settings.
- [x] Full build: 286/286 passed, 0 failed, 75.55% command coverage.
- [x] Fixture-only plan and preview WhatIf: exit 0; no plan or workspace artifact.
- [x] Compatibility/hygiene: 17 exports, Apply/Preflight sets, PATH unchanged, diff check clean, no credential or raw-host-path match.

## Open questions

- None. The implementation design and isolated feature branch were approved.

## Handoff

- Design/plan commit: `37a9882`.
- Analyzer cleanup implementation commit: `676b784`.
- Plane verification comment: `345f79e5-7641-4964-9b8c-7d5f5ef86917`.
- Independent Sol review was unavailable because the session child-thread limit had already been exhausted; complete local line-level review found no unresolved issue.

## Next action

Commit this verification record, confirm a clean worktree, and hand the feature branch to a human reviewer without pushing or merging it.
