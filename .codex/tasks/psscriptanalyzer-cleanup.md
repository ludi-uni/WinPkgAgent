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

## Acceptance criteria

- [ ] PSScriptAnalyzer 1.25.0 reports zero findings for `src` and `scripts`.
- [ ] A RED test proves `Set-WpaRunStage -WhatIf` did not previously protect the write; the implementation makes it GREEN.
- [ ] Exported command names and Apply/Preflight parameter sets are unchanged.
- [ ] Focused affected tests pass using fixtures/injected adapters only.
- [ ] Full build passes with at least 285 tests, zero failures, and at least 75% command coverage.
- [ ] Fixture-only plan/preview WhatIf writes no plan or workspace artifact.
- [ ] PATH is unchanged and the diff contains no secret or raw host diagnostic.
- [ ] Only approved files are committed on the feature branch.
- [ ] WINPKGAG-4 receives verification and remains in Review fallback rather than Done.

## Tests

- [x] Pre-change build under approved normal execution: 285/285 passed; 75.47% coverage; build completed.
- [x] Pre-change managed build: tests and coverage passed; JUnit export alone was blocked by `Get-CimInstance` access denial.
- [ ] Focused RED/GREEN stage test.
- [ ] Affected module test groups.
- [ ] Exact PSScriptAnalyzer gate.
- [ ] Full build and fixture-only CLI WhatIf smoke.

## Open questions

- None. The implementation design and isolated feature branch were approved.

## Next action

Commit the approved design/plan, then begin Task 1 with the failing stage-WhatIf test.
