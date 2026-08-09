# Usage

The intended sequence is inventory, plan, approval, apply, and verify:

```powershell
$inventory = Get-WpaInventory -PolicyPath .\config\policy.default.yaml -OutputPath .\artifacts\inventory.json
$plan = New-WpaPlan -ManifestPath .\config\packages.example.yaml -PolicyPath .\config\policy.default.yaml -InventoryPath .\artifacts\inventory.json -OutputPath .\artifacts\plan.json -MarkdownPath .\artifacts\plan.md
Approve-WpaPlan -PlanPath .\artifacts\plan.json -OutputPath .\artifacts\plan.approval.json
Invoke-WpaPlan -PlanPath .\artifacts\plan.json -PolicyPath .\config\policy.default.yaml -Preflight
Invoke-WpaPlan -PlanPath .\artifacts\plan.json -ApprovalPath .\artifacts\plan.approval.json -PolicyPath .\config\policy.default.yaml
```

The exported command help and schemas define the exact parameter surface. Start with fixture-only `-WhatIf`; never point tests at a production machine. If `powershell-yaml` 0.4.12 is unavailable, install it explicitly according to environment policy; the module does not install it.

Choose the policy explicitly; it is never inferred from the host or Codex. Use `./config/policy.codex.yaml` for a Scoop-only Codex-constrained scope and `./config/policy.desktop.yaml` or `./config/policy.default.yaml` for desktop WinGet+Scoop scope. Pass the same `-PolicyPath` to environment, inventory, plan, apply, and verification commands.

Inventory is schema v2 and records `policyHash` and `managerScope`. Regenerate schema-v1 or unscoped inventories before planning. A policy hash or manager scope mismatch fails closed as `INVENTORY_SCOPE_MISMATCH`.

If `Test-WpaEnvironment` reports `managers.scoop: false`, follow the [official Scoop installation instructions](https://github.com/ScoopInstaller/Install#installation) in a regular, non-admin PowerShell, then open a new session and regenerate inventory and plan. The tool does not install Scoop automatically.

Scoop inventory runs `scoop status --local` and does not fetch remotes. Its `availableVersion` values therefore reflect the local bucket manifests. If `scoop --version` reports a development-branch Git commit instead of a release semantic version, WinPkgAgent leaves the manager `partial` rather than guessing a version. It does not change the Scoop branch or configuration automatically.

CLI exit codes are stable for automation: `0` success or `-WhatIf`, `1` command/preflight error, `2` invalid validation result, `3` partial apply failure, `4` verification failure, and `5` reboot required (the tool never reboots automatically).

## Safe preview

Use the same fixture manifest with an explicit policy:

```powershell
pwsh ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.codex.yaml -WorkspacePath ./.wpa
pwsh ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.desktop.yaml -WorkspacePath ./.wpa
```

For `preview`, exit code `0` means ready, `1` means a fatal trust/publication failure with no completed run, and `2` means a completed reviewable blocked run with `blockedReasons`. Preview never approves, applies, installs dependencies, mutates `PATH`, adds sources, elevates, or remaps managers.

Review and apply remain separate, human-controlled steps:

```powershell
pwsh ./scripts/winpkg-agent.ps1 show-run -RunPath <run-path>
pwsh ./scripts/winpkg-agent.ps1 approve-run -RunPath <run-path>
pwsh ./scripts/winpkg-agent.ps1 invoke-run -RunPath <run-path> -WhatIf
pwsh ./scripts/winpkg-agent.ps1 invoke-run -RunPath <run-path>
```
## Run workspace

Use `New-WpaRun -ManifestPath ./packages.yaml -PolicyPath ./policy.yaml -WorkspacePath ./.wpa` to keep related artifacts together. Then use `Show-WpaRun`, `Approve-WpaRun`, and `Invoke-WpaRun -WhatIf` or `Invoke-WpaRun`. A previous journal blocks a new apply until it is inspected. After a reboot-required result, use `Resume-WpaVerification` explicitly; no automatic reboot or resume is scheduled.

For CLI resume verification, keep the policy explicit:

```powershell
pwsh ./scripts/winpkg-agent.ps1 resume-verify `
  -PlanPath ./artifacts/plan.json `
  -ApplyResultPath ./artifacts/apply-result.json `
  -PolicyPath ./config/policy.default.yaml `
  -VerifyOutputPath ./artifacts/verify-result.json `
  -WhatIf
```

With `policy.codex.yaml`, a manifest item declared for WinGet is blocked as `MANAGER_NOT_ALLOWED`; it is not remapped to Scoop. `MANAGER_UNAVAILABLE` identifies an unavailable allowed manager, while `INVENTORY_SCOPE_MISMATCH` identifies a policy hash/scope mismatch.

`Initialize-WpaProject` creates safe starter files without installing Scoop, changing PATH, changing execution policy, or overwriting existing files. `Export-WpaManifestCandidate` creates a separate `reviewStatus: pending` candidate and never promotes it to the active manifest.

Use `Export-WpaUnmanagedCandidate -InventoryPath ./artifacts/inventory.json -OutputPath ./artifacts/unmanaged-candidate.json` to record WinGet list entries that are not present in the export inventory. The JSON artifact is review-only; source-less ARP/MSIX identifiers remain `manual-mapping` and are never promoted automatically.

If App Installer is unavailable in a managed execution context, do not change `PATH`, AppX permissions, or ownership. Run inventory from the regular user's PowerShell 7 with the same explicit policy:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File ./scripts/winpkg-agent.ps1 inventory `
  -PolicyPath ./config/policy.desktop.yaml `
  -OutputPath ./artifacts/migration-inventory.json
```

The CLI does not expose arbitrary package-manager executable path overrides. If the manager still cannot be verified in the regular user context, retain the `partial` / `failed` result and stop before plan or apply. WinPkgAgent does not change `PATH`, AppX permissions, or ownership.

## PowerShell runtime diagnostics

`Test-WpaEnvironment -PowerShellPath 'D:\Tools\PowerShell\7\pwsh.exe'` applies an absolute path for the current invocation only. A policy may contain `runtime.powershellPath` for a configured absolute path. Invalid explicit paths fail closed and do not fall back silently. The runtime probe uses `-NoLogo -NoProfile -NonInteractive` and validates JSON `PSEdition` and `PSVersion`.
