# winpkg-agent

`winpkg-agent` is a PowerShell 7.4+ module for a human-approved workflow around WinGet and Scoop: **inventory → plan → approval → apply → verify**.

## Safety first

> **Back up important data before applying any package changes. Package managers and operating-system changes can have side effects that this project cannot undo.**

Version 0.1 is deliberately narrow: it accepts `state: present`, has no uninstall/elevation/reboot/driver/firmware path, and fails closed when inventory or policy is incomplete, stale, ambiguous, or tampered. Planning and `-WhatIf` are read-only. Tests never install or upgrade a real package.

The module is intentionally conservative. Treat the schemas, policy, and tests as the source of truth; unsupported manager output remains partial/failed rather than being guessed.

## Purpose and non-goals

The project is a safety orchestration layer for agents and humans, not a replacement package manager. It declares desired presence, calculates reviewable differences, gates them with separate human approval, applies only approved install/update operations, and verifies the result. It does not remove packages, add sources, elevate privileges, update drivers/BIOS/firmware, reboot Windows, promise rollback, or make ambiguous version decisions.

## Package ownership

- **WinGet:** desktop applications such as browsers, editors, Git, Docker Desktop, OBS Studio, Blender, and Discord.
- **Scoop:** CLI/development/portable tools such as ffmpeg, jq, ripgrep, fd, yt-dlp, aria2, ImageMagick, mise, uv, just, age, and rclone.

Each logical package and each `(manager, id)` pair must be unique. Suspected cross-manager product duplication is reported for human review and is never auto-corrected.

Every declared package also requires an explicit source and category. Scoop inventory and installs are supported, but Scoop upgrades are blocked in v0.1 because the official update command cannot pin the exact version approved in a plan.

## Workflow

1. `Get-WpaInventory -PolicyPath ...` records only the managers selected by the explicit policy, plus capabilities and uncertainty.
2. `New-WpaPlan` compares a manifest with that inventory and emits deterministic JSON/Markdown artifacts.
3. `Approve-WpaPlan` is a separate interactive action requiring typed digest confirmation.
4. `Invoke-WpaPlan` revalidates hashes, approval, environment, policy, freshness, and manager availability before sequential execution.
5. Verification reacquires inventory and reports uncertainty; it never claims rollback.

Policy selection is explicit and is never inferred from the host, PATH, or Codex. Use `config/policy.codex.yaml` for a Scoop-only Codex-constrained scope, or `config/policy.desktop.yaml` / `config/policy.default.yaml` for a desktop WinGet+Scoop scope. The same policy file must be used for environment checks, inventory, planning, apply, and verification.

Inventory artifacts are schema v2 and carry `policyHash` and `managerScope`. Regenerate any schema-v1 or unscoped inventory before planning. Plans fail closed when the inventory policy hash or manager scope does not match the selected policy (`INVENTORY_SCOPE_MISMATCH`).

See [docs/architecture.md](docs/architecture.md), [docs/safety.md](docs/safety.md), and [docs/usage.md](docs/usage.md).

## Requirements and installation

Use PowerShell 7.4 or newer. Install the runtime parser explicitly; winpkg-agent never installs dependencies:

```powershell
Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser
Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1
```

WinGet and Scoop remain responsible for their own package state and command contracts. Approval is a human-only, interactive typed-digest confirmation; AI agents may prepare plans but cannot approve them.

If `Test-WpaEnvironment` reports `managers.scoop: false`, install Scoop manually before collecting inventory. The project never installs Scoop or changes execution policy automatically. From a regular, non-admin PowerShell, follow the [official Scoop installation instructions](https://github.com/ScoopInstaller/Install#installation):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest https://get.scoop.sh -OutFile ./install-scoop.ps1
Get-Content ./install-scoop.ps1
./install-scoop.ps1
scoop --version
Get-Command scoop
```

Manager discovery is not limited to the inherited `PATH`. For non-interactive hosts such as Codex, winpkg-agent also checks the current user's standard Scoop shim and Windows App execution alias. The resolved executable is used consistently for inventory and package operations, while the path is kept in memory and is not written to artifacts. Custom installations must still be exposed through the process `PATH`; winpkg-agent does not persistently modify `PATH` or install a manager.

When the module is imported, it does not modify the current process `PATH`, start managers, write files, or install dependencies. Each manager operation uses its resolved absolute executable path directly:

```powershell
Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1 -Force
Test-WpaEnvironment
```

Typical plan actions are `no-op`, `install`, `upgrade`, `blocked`, `unmanaged`, or `unknown`, each with a reason code. For command failures and partial inventory, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Quick start

```powershell
Test-WpaEnvironment
Get-WpaInventory -PolicyPath ./config/policy.default.yaml `
  -OutputPath ./artifacts/inventory.json
Test-WpaManifest -Path ./config/packages.example.yaml
New-WpaPlan -ManifestPath ./config/packages.example.yaml `
  -PolicyPath ./config/policy.default.yaml `
  -InventoryPath ./artifacts/inventory.json `
  -OutputPath ./artifacts/plan.json `
  -MarkdownPath ./artifacts/plan.md
Show-WpaPlan -PlanPath ./artifacts/plan.json
# A human reviews and runs Approve-WpaPlan interactively.
Invoke-WpaPlan -PlanPath ./artifacts/plan.json `
  -PolicyPath ./config/policy.default.yaml -Preflight
```

For a Codex/Scoop-only inventory and plan, select the policy explicitly:

```powershell
Get-WpaInventory -PolicyPath ./config/policy.codex.yaml -OutputPath ./artifacts/codex-inventory.json
New-WpaPlan -ManifestPath ./config/packages.example.yaml `
  -PolicyPath ./config/policy.codex.yaml `
  -InventoryPath ./artifacts/codex-inventory.json `
  -OutputPath ./artifacts/codex-plan.json `
  -MarkdownPath ./artifacts/codex-plan.md
```

Under the Codex/Scoop-only policy, a manifest package declared for WinGet is blocked with `MANAGER_NOT_ALLOWED`. winpkg-agent does not fallback or remap it to Scoop, change `PATH` or execution policy, alter App Installer/OS policy, elevate, install managers, or bypass approval. `MANAGER_UNAVAILABLE` means an allowed manager could not be used; `INVENTORY_SCOPE_MISMATCH` means the inventory's policy hash or manager scope is not the selected policy.

Example plan row:

```text
PACKAGE_NOT_INSTALLED  install  scoop/ripgrep  risk=low
```

`-WhatIf` completes all read-side integrity and freshness checks but invokes no mutating adapter. Remove it only after reviewing the plan, making backups, and completing the separate human approval. Approval fixes a digest and records explicit consent; it is not cryptographic identity proof and cannot make package-manager operations reversible.

## Dependencies

- PowerShell 7.4 or newer
- Runtime YAML support: `powershell-yaml` 0.4.12 (Apache-2.0); the module detects it and reports installation guidance, but never installs it silently.
- Development/CI: Pester 5.x and PSScriptAnalyzer 1.25.x, installed explicitly by the workflow.

## Development

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md). The official-action-only Windows CI validates schemas/samples, imports the module, runs analyzer and Pester, and performs a fixture-only `-WhatIf` smoke test. It never mutates real packages.

## Project status and reporting

Unsupported manager contracts are surfaced as partial/failed inventory, not guessed. Open an issue with the command output, redacted logs, PowerShell version, and fixture (never credentials or personal paths). See [SECURITY.md](SECURITY.md) for vulnerability reporting.

This software is provided “as is”; review every generated plan and maintain your own backups.

## PowerShell 7 runtime discovery

WinPkgAgent requires `pwsh.exe` from PowerShell 7.4 or newer and never falls back to Windows PowerShell `powershell.exe`. Runtime discovery checks the current Core process first, then `Get-Command pwsh.exe`, standard MSI/preview locations, the Windows Apps alias, and the .NET tool location. It never changes user or machine PATH.

For a ZIP or custom installation, configure an absolute path without persisting it automatically:

```yaml
runtime:
  powershellPath: 'D:\Tools\PowerShell\7\pwsh.exe'
```

Or diagnose a one-time path with `Test-WpaEnvironment -PowerShellPath 'D:\Tools\PowerShell\7\pwsh.exe'`. If Codex, Windows Terminal, or VS Code was open while PowerShell was installed, restart that host or configure the absolute path explicitly.

## License

MIT; Copyright (c) 2026 Ludi. See [LICENSE](LICENSE).
