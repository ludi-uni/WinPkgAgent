# Safe planning fixture

`inventory.sample.json` is synthetic and changes no computer. With the explicitly installed YAML dependency, generate a review-only plan:

```powershell
Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1
New-WpaPlan -ManifestPath ./config/packages.example.yaml `
  -PolicyPath ./config/policy.default.yaml `
  -InventoryPath ./examples/inventory.sample.json `
  -OutputPath ./artifacts/plan.json `
  -MarkdownPath ./artifacts/plan.md
```

The environment ID is intentionally synthetic, so the plan cannot pass live apply preflight. No approval fixture is provided; approval must be performed by a human for a current live plan.
