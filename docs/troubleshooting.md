# Troubleshooting

## YAML dependency unavailable

Install `powershell-yaml` 0.4.12 explicitly using your organization’s approved PowerShell repository and verify its license. The module intentionally does not install dependencies.

## Inventory is partial or failed

Check PowerShell 7.4+, manager availability, export command output, timeout diagnostics, and the relevant contract fixture. Do not convert a parser mismatch into guessed package state; partial state blocks relevant mutations.

## Plan cannot be applied

Regenerate inventory and plan when hashes, expiry, environment identity, policy, manager availability, or freshness checks fail. Review the plan digest and obtain a new interactive approval. AI agents cannot approve it.

## CI differs locally

Use the same explicit Pester 5.x and PSScriptAnalyzer 1.25.x ranges as CI. Report unavailable tools and exact commands rather than skipping tests.
