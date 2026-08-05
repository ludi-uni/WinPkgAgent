# Usage

The intended sequence is inventory, plan, approval, apply, and verify:

```powershell
$inventory = Get-WpaInventory -OutputPath .\artifacts\inventory.json
$plan = New-WpaPlan -ManifestPath .\config\packages.example.yaml -PolicyPath .\config\policy.default.yaml -InventoryPath .\artifacts\inventory.json -OutputPath .\artifacts\plan.json -MarkdownPath .\artifacts\plan.md
Approve-WpaPlan -PlanPath .\artifacts\plan.json -OutputPath .\artifacts\plan.approval.json
Invoke-WpaPlan -PlanPath .\artifacts\plan.json -PolicyPath .\config\policy.default.yaml -Preflight
Invoke-WpaPlan -PlanPath .\artifacts\plan.json -ApprovalPath .\artifacts\plan.approval.json -PolicyPath .\config\policy.default.yaml
```

The exported command help and schemas define the exact parameter surface. Start with fixture-only `-WhatIf`; never point tests at a production machine. If `powershell-yaml` 0.4.12 is unavailable, install it explicitly according to environment policy; the module does not install it.

If `Test-WpaEnvironment` reports `managers.scoop: false`, follow the [official Scoop installation instructions](https://github.com/ScoopInstaller/Install#installation) in a regular, non-admin PowerShell, then open a new session and regenerate inventory and plan. The tool does not install Scoop automatically.

CLI exit codes are stable for automation: `0` success or `-WhatIf`, `1` command/preflight error, `2` invalid validation result, `3` partial apply failure, `4` verification failure, and `5` reboot required (the tool never reboots automatically).
## Run workspace

Use `New-WpaRun -ManifestPath ./packages.yaml -PolicyPath ./policy.yaml -WorkspacePath ./.wpa` to keep related artifacts together. Then use `Show-WpaRun`, `Approve-WpaRun`, and `Invoke-WpaRun -WhatIf` or `Invoke-WpaRun`. A previous journal blocks a new apply until it is inspected. After a reboot-required result, use `Resume-WpaVerification` explicitly; no automatic reboot or resume is scheduled.

`Initialize-WpaProject` creates safe starter files without installing Scoop, changing PATH, changing execution policy, or overwriting existing files. `Export-WpaManifestCandidate` creates a separate `reviewStatus: pending` candidate and never promotes it to the active manifest.

## PowerShell runtime diagnostics

`Test-WpaEnvironment -PowerShellPath 'D:\Tools\PowerShell\7\pwsh.exe'` applies an absolute path for the current invocation only. A policy may contain `runtime.powershellPath` for a configured absolute path. Invalid explicit paths fail closed and do not fall back silently. The runtime probe uses `-NoLogo -NoProfile -NonInteractive` and validates JSON `PSEdition` and `PSVersion`.
