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

## Approval file is missing

`Invoke-WpaPlan -Preflight` and CLI `invoke -WhatIf` do not require an approval artifact. Normal Apply requires a separate approval artifact. Review the plan and create it interactively as a human:

```powershell
Approve-WpaPlan -PlanPath ./artifacts/plan.json -OutputPath ./artifacts/plan.approval.json
```

Then pass that path to `Invoke-WpaPlan`. AI agents cannot create or approve this artifact.

## Inventory is partial or failed

Check PowerShell 7.4+, manager availability, export command output, timeout diagnostics, and the relevant contract fixture. Do not convert a parser mismatch into guessed package state; partial state blocks relevant mutations.

## Plan cannot be applied

Regenerate inventory and plan when hashes, expiry, environment identity, policy, manager availability, or freshness checks fail. Review the plan digest and obtain a new interactive approval. AI agents cannot approve it.

## CI differs locally

Use the same explicit Pester 5.x and PSScriptAnalyzer 1.25.x ranges as CI. Report unavailable tools and exact commands rather than skipping tests.
