# Troubleshooting

## YAML dependency unavailable

Install `powershell-yaml` 0.4.12 explicitly using your organization’s approved PowerShell repository and verify its license. The module intentionally does not install dependencies.

## Scoop is unavailable

Run `Test-WpaEnvironment`. Discovery first uses the inherited `PATH`, then checks the current user's standard Scoop shim location. This supports non-interactive hosts whose PATH was captured before Scoop was installed:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest https://get.scoop.sh -OutFile ./install-scoop.ps1
Get-Content ./install-scoop.ps1
./install-scoop.ps1
scoop --version
Get-Command scoop
```

If the manager is not installed, install it manually from a regular, non-admin PowerShell using the [official Scoop installation instructions](https://github.com/ScoopInstaller/Install#installation). For a custom installation, expose its executable through the process PATH before starting winpkg-agent. winpkg-agent never installs Scoop, changes execution policy, or persistently modifies PATH implicitly.

WinGet discovery also checks the current user's Windows App execution alias. If both `Get-Command winget` and `Test-WpaEnvironment` fail, verify the App Installer registration in the same Windows user context:

```powershell
Get-Command winget -ErrorAction SilentlyContinue
Get-AppxPackage -Name Microsoft.DesktopAppInstaller | Select-Object Name, Version, InstallLocation
```

The resolved manager path is used consistently for inventory, install, and upgrade, but is kept in memory and is not written to inventory, plan, or result artifacts.

Importing the module does not modify the current process `PATH`. Manager operations use the resolved absolute executable path directly.

## PowerShell 7 is not detected

WinPkgAgent requires PowerShell 7.4 or newer and specifically `pwsh.exe`; it never falls back to `powershell.exe`. Check `Get-Command pwsh.exe`, `where.exe pwsh`, and the standard locations under `$env:ProgramFiles`, `$env:LOCALAPPDATA\Microsoft\WindowsApps`, and `$env:USERPROFILE\.dotnet\tools`. Restart Codex, Windows Terminal, or VS Code after installing PowerShell, or pass `-PowerShellPath` to `Test-WpaEnvironment`. ZIP installations generally require an explicit absolute path. WinPkgAgent does not modify PATH.

## Approval file is missing

`Invoke-WpaPlan -Preflight` and CLI `invoke -WhatIf` do not require an approval artifact. Normal Apply requires a separate approval artifact. Review the plan and create it interactively as a human:

```powershell
Approve-WpaPlan -PlanPath ./artifacts/plan.json -OutputPath ./artifacts/plan.approval.json
```

Then pass that path to `Invoke-WpaPlan`. AI agents cannot create or approve this artifact.

## Inventory is partial or failed

Check PowerShell 7.4+, the explicitly selected `-PolicyPath`, manager availability, export command output, timeout diagnostics, and the relevant contract fixture. Policy is never inferred from the host or Codex. Inventory is schema v2 and must contain `policyHash` and `managerScope`; regenerate schema-v1 or unscoped artifacts before planning. Do not convert a parser mismatch into guessed package state; partial state blocks relevant mutations.

`MANAGER_UNAVAILABLE` means an allowed manager could not be resolved or its inventory is unavailable. `INVENTORY_SCOPE_MISMATCH` means the inventory policy hash or manager scope differs from the selected policy. Under `config/policy.codex.yaml`, a manifest package declared for WinGet is intentionally blocked as `MANAGER_NOT_ALLOWED`; it is not remapped to Scoop. The tool does not change PATH or execution policy, alter App Installer/OS policy, elevate, install managers, or bypass approval.

For a Codex/Scoop-only inventory, use `Get-WpaInventory -PolicyPath ./config/policy.codex.yaml -OutputPath ./artifacts/codex-inventory.json`. For desktop WinGet+Scoop, use `./config/policy.desktop.yaml` or `./config/policy.default.yaml`. Pass the same policy path to resume verification with `Resume-WpaVerification` or CLI `resume-verify`.

## Plan cannot be applied

Regenerate inventory and plan when hashes, expiry, environment identity, policy, manager availability, or freshness checks fail. Review the plan digest and obtain a new interactive approval. AI agents cannot approve it.

## CI differs locally

Use the same explicit Pester 5.x and PSScriptAnalyzer 1.25.x ranges as CI. Report unavailable tools and exact commands rather than skipping tests.
