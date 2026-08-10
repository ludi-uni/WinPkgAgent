# Package migration task state

## Objective

Prepare as many current WinGet/Scoop-detected applications as possible for human-reviewed management without changing package state.

## Scope

- Use PowerShell 7.4+ through the absolute `pwsh.exe` path.
- Normalize empty WinGet/Scoop exports.
- Prefer process-compatible Scoop shims over `.ps1` files.
- Generate pending candidate manifests with safe logical names and migration warnings.
- Do not approve or invoke package mutations.

## Evidence

- Pester 5.6.1: focused manager/migration tests `52/52`; full suite `285/285`; coverage `75.47%` against a `75%` threshold.
- Build validation and fixture-only CLI `plan`/`preview -WhatIf` smoke checks pass without writing plan or workspace artifacts.
- Managed Codex shell: Scoop `export`, `--version`, and `status` return exit code 0 but emit `dubious ownership` on stderr; inventory fails closed with 0 packages.
- Normal user PowerShell: the same read-only Scoop commands have clean stderr; export is a valid empty set and local status is recognized. Public inventory remains `partial` with 0 packages because the current non-release Scoop branch reports a Git commit instead of a release semantic version.
- Current host-local review artifacts are `artifacts/codex-inventory.json` (managed-shell failed result) and `artifacts/codex-inventory.user.json` (normal-user partial result). Earlier migration/unmanaged candidate artifacts are not current.
- No install, update, uninstall, approval, apply, elevation, source addition, branch change, or ownership repair was invoked.

## Verification limits

- PSScriptAnalyzer 1.25.0 is not installed locally. The pinned analyzer remains a CI-only gate; dependencies were not installed automatically.
- There are currently no Scoop-managed application packages in the normal-user export, so a non-empty live Scoop inventory is not yet demonstrated.
- Supporting a non-release Scoop Git commit as a manager version requires a separate version-identity design decision. The current fail-closed behavior is intentional.
- No active manifest or approval digest was created because source, category, manager ownership, and reinstall impact require human review.
- ARP/MSIX and source-less observations are deliberately isolated from the active manifest path.

## Next action

Decide whether Scoop development-branch commits should receive a separately designed version identity or whether live verification should use a released Scoop branch. WinPkgAgent must not change that branch automatically. To demonstrate a non-empty live Scoop inventory, first install a package manually under the normal user context, then regenerate inventory. Existing Windows applications should be reviewed under the explicit desktop/WinGet policy rather than remapped to Scoop. Stop before `Approve-WpaPlan` and `Invoke-WpaPlan` until the user explicitly approves a resulting plan.
