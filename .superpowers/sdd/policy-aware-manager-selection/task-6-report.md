# Task 6 report

Status: complete

Commit: docs: document explicit manager policy selection

Changed files:

- `README.md` and `README.ja.md`: explicit policy selection, policy-scoped inventory, schema-v2 regeneration, mismatch behavior, and Codex/Scoop-only blocking guidance.
- `docs/usage.md` and `docs/usage.ja.md`: policy-aware inventory and resume-verify examples plus migration guidance.
- `docs/architecture.md` and `docs/architecture.ja.md`: policy hash/scope binding and manager reason-code behavior.
- `docs/troubleshooting.md`: scope, availability, and no-bypass troubleshooting guidance.
- `CHANGELOG.md`: unreleased documentation note.
- `tests/Integration/Cli.Tests.ps1`: static assertions for policy examples, scope guidance, reason codes, resume policy propagation, and schema-v2 sample validity.

RED:

- Focused CLI Pester: 4 passed, 1 failed as expected because the new documentation assertions were not yet satisfied.

GREEN:

- Focused CLI Pester with `-DisableRegistry`: 5 passed, 0 failed, 0 skipped.
- `git diff --check`: passed.

Concerns:

- Pester emits the repository-known managed `Get-CimInstance` access-denied coverage metadata warning; it does not fail the focused tests.
- No real WinGet or Scoop manager command was invoked.
- The report commit identifier is the commit containing this report.
