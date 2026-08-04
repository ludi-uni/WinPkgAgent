# Usage

The intended sequence is inventory, plan, approval, apply, and verify:

```powershell
$inventory = Get-WpaInventory -OutputPath .\artifacts\inventory.json
$plan = New-WpaPlan -ManifestPath .\config\packages.example.yaml -PolicyPath .\config\policy.default.yaml -InventoryPath .\artifacts\inventory.json -OutputPath .\artifacts\plan.json -MarkdownPath .\artifacts\plan.md
Approve-WpaPlan -PlanPath .\artifacts\plan.json -OutputPath .\artifacts\approval.json
Invoke-WpaPlan -PlanPath .\artifacts\plan.json -ApprovalPath .\artifacts\approval.json -PolicyPath .\config\policy.default.yaml -WhatIf
Invoke-WpaPlan -PlanPath .\artifacts\plan.json -ApprovalPath .\artifacts\approval.json -PolicyPath .\config\policy.default.yaml
```

The exported command help and schemas define the exact parameter surface. Start with fixture-only `-WhatIf`; never point tests at a production machine. If `powershell-yaml` 0.4.12 is unavailable, install it explicitly according to environment policy; the module does not install it.

CLI exit codes are stable for automation: `0` success or `-WhatIf`, `1` command/preflight error, `2` invalid validation result, `3` partial apply failure, `4` verification failure, and `5` reboot required (the tool never reboots automatically).
