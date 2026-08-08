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

- PowerShell: 7.6.3 during the live read-only run.
- Current inventory after fixes: status `success`, WinGet `success`, Scoop `success`, 88 packages, 0 warnings.
- Candidate artifact: `artifacts/migration-candidate.yaml`.

## Verification limits

- Local shell has Pester 3.4.0; repository tests use Pester 5.x assertions. Direct PowerShell 7 assertions and live read-only smoke checks are available; the full Pester suite still needs the declared development dependency.
- No active manifest or approval digest was created because source, category, manager ownership, and reinstall impact require human review.

## Next action

Review `artifacts/migration-candidate.yaml`, then create an active manifest only after confirming each package and its source/category. Stop before `Approve-WpaPlan` and `Invoke-WpaPlan` until the user explicitly approves the resulting plan.
