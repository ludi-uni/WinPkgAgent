# Architecture

The module separates pure data logic from adapters and artifact I/O. Public commands orchestrate explicit stages; no hidden mutable state is shared between stages.

External processes cross one `System.Diagnostics.ProcessStartInfo` adapter using `ArgumentList`, redirected streams, structured exit metadata, and explicit timeouts. Inventory is export-first: WinGet uses `winget export --include-versions`; Scoop uses `scoop export`. Strict English/Japanese fallback parsers are used only where update metadata is unavailable. Scoop's update reporting can be limited by its export contract and therefore may remain partial/unknown; the system never guesses.

Every manifest package declares an explicit source and category. Driver, BIOS, UEFI, and firmware categories are non-relaxable in v0.1. WinGet inventory never accepts source agreements on the user's behalf. Scoop's official `update` command selects the current bucket manifest and cannot pin an exact approved target version, so Scoop upgrades are blocked in v0.1; Scoop inventory and installs remain supported.

Plans contain immutable inputs/actions and separately generated metadata. `contentHash` excludes itself and non-deterministic plan metadata. Approval is a separate interactive-only artifact. Apply revalidates schema, plan/full hashes, approval digest/expiry, environment, policy, inventory freshness, manager availability, operation count, and blocked status before sequential execution.

Verification reacquires inventory through the same adapter boundary and records uncertainty; it does not claim rollback.

Run workspaces are a thin orchestration layer around these commands. They fix artifact names relative to one run directory, reject traversal and reparse points, and refuse a new apply when a journal already exists. `Resume-WpaVerification` is an explicit, user-invoked read-only continuation after reboot-required apply.

PowerShell runtime discovery is a separate read-only boundary. It returns an artifact-safe fingerprint (path hash, file hash, version, edition, signature metadata, and source) while retaining the resolved path only in memory. External probes use the existing absolute-path process adapter and fixed no-profile/non-interactive arguments.

Apply writes an atomic `apply-result.journal.json` snapshot immediately before and after each attempted mutation so a process interruption does not erase the operation boundary.
