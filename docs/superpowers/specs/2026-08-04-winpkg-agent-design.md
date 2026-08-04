# winpkg-agent Design

## Objective

Build a PowerShell 7 module that lets humans and AI agents manage WinGet and Scoop packages through a fail-closed `inventory -> plan -> approval -> apply -> verify` workflow. The attached implementation instruction is the normative product specification; this document records the chosen implementation shape.

## Architecture

The module dot-sources small public commands and private helpers. Pure helpers own parsing, schema checks, canonical JSON, hashes, policy evaluation, version classification, and plan generation. External processes are reachable only through a `System.Diagnostics.ProcessStartInfo` adapter using `ArgumentList`, redirected streams, explicit timeouts, and structured results. Public commands orchestrate the five stages without sharing hidden mutable state.

Inventory prefers machine-readable manager contracts: `winget export --include-versions` and `scoop export`. Upgrade metadata that is unavailable from those exports is accepted only through isolated strict parsers with English and Japanese fixtures. A parser mismatch produces partial/failed inventory, never guessed package state.

Plans contain immutable inputs and actions plus separately generated metadata. `contentHash` is calculated from canonical JSON after excluding `contentHash` itself and non-deterministic metadata (`planId`, creation and expiry timestamps). The full plan hash fixes the serialized plan used by approval. Approval is a separate interactive-only file and is never emitted by planning or invocation.

Apply revalidates schemas, both hashes, approval digest and expiry, environment identity, current policy hash, current inventory hash, manager availability, operation count, and blocked status before running anything. Operations execute sequentially and stop on first failure. Verification always reacquires inventory through the same adapter boundary and records uncertainty rather than claiming rollback.

## Safety boundaries

- No uninstall operation, absent state, elevation, reboot, source addition, driver, BIOS, firmware, or arbitrary command execution path exists in v0.1.
- Manifest identifiers, sources, versions, verification command names/arguments, and output paths are allow-list validated.
- The environment identifier is a SHA-256 digest of stable, non-secret host attributes; raw host and user values are not persisted.
- Atomic writes create a same-directory temporary file, reject reparse-point destinations and traversal outside the caller-selected parent, then replace/move the file.
- Logs and command diagnostics redact token-like values, user profile paths, and common credential assignments before persistence.
- `Approve-WpaPlan` requires an interactive host and typed digest confirmation. No force switch, environment variable, or co-located approval shortcut is implemented.
- `Invoke-WpaPlan -WhatIf` performs every read-side validation but never calls a mutating adapter.

## Dependencies

PowerShell 7.4 or newer is required. YAML parsing uses `powershell-yaml` 0.4.12 (Apache-2.0, built on YamlDotNet); the module detects it and fails with installation guidance but never installs it. Development and CI use Pester 5.x and PSScriptAnalyzer 1.25.x. Runtime schema validation uses PowerShell's `Test-Json -SchemaFile`.

## Testing

Pester tests exercise pure behavior and inject process/inventory adapters at the narrow external boundary. Contract fixtures cover WinGet/Scoop JSON and strict fallback parsing in English and Japanese. Tests never invoke real install, upgrade, uninstall, elevation, or restart operations. CI runs on Windows, installs pinned development dependencies explicitly, validates schemas and samples, imports the module, runs analyzer and Pester with JUnit/coverage, and executes a CLI `-WhatIf` smoke test against fixtures.

## Design review

The design intentionally does not promise manager-complete inventory when a stable machine-readable contract is unavailable. Such states are surfaced as partial and block relevant mutations. There are no placeholders, implicit overrides, or rollback guarantees.
