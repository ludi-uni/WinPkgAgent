# Troubleshooting

## YAML dependency unavailable

Install `powershell-yaml` 0.4.12 explicitly using your organization’s approved PowerShell repository and verify its license. The module intentionally does not install dependencies.

## Scoop is unavailable

Run `Test-WpaEnvironment`. If `managers.scoop` is `false`, Scoop is not discoverable on the current `PATH`. Install it manually from a regular, non-admin PowerShell using the [official Scoop installation instructions](https://github.com/ScoopInstaller/Install#installation):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
scoop --version
Get-Command scoop
```

Start a new PowerShell session if needed, then rerun `Test-WpaEnvironment`, `Get-WpaInventory`, and `New-WpaPlan`. winpkg-agent never installs Scoop or changes execution policy implicitly.

## Approval file is missing

`Invoke-WpaPlan` requires a separate approval artifact even with `-WhatIf`. Review the plan and create it interactively as a human:

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
