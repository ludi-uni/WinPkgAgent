# Security policy

## Scope

The project is designed to fail closed around package-manager operations. It does not promise rollback, elevation, reboot handling, or complete inventory when a stable manager contract is unavailable.

## Reporting

Please report suspected vulnerabilities privately to the repository maintainers before public disclosure. Include a minimal reproduction, affected version/commit, PowerShell version, and redacted logs. Do not include credentials, tokens, personal paths, host identifiers, or package-manager account data. If no private channel is configured yet, open a minimal issue asking for a security contact without attaching exploit details.

## Security boundaries

Manifest identifiers, sources, versions, verification command names/arguments, and output paths are allow-listed. External processes use executable-plus-argument arrays and explicit timeouts. Atomic writes reject traversal and reparse-point destinations. Diagnostics redact token-like values, profile paths, and common credential assignments. Approval requires an interactive host and typed digest confirmation.

## Release handling

Security fixes should include a regression test, an entry in `CHANGELOG.md`, and a clear statement of whether an upgrade or configuration change is required. Before publishing a release, confirm that `LICENSE` retains the approved `Copyright (c) 2026 Ludi` notice.

## Run workspace and diagnostics

Run artifacts are constrained to the run directory and use fixed filenames. Existing journals require manual inspection before another apply. Diagnostic logging is bounded and best-effort redacted; review it before sharing. Manager ACL and signature checks are conservative and an unavailable assessment remains blocked.
