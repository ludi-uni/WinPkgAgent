# Dependencies and licenses

| Dependency | Use | Version policy | License |
| --- | --- | --- | --- |
| PowerShell | Runtime | 7.4+ | Microsoft terms |
| powershell-yaml | Runtime YAML parsing | 0.4.12 | Apache-2.0 (built on YamlDotNet) |
| Pester | Development/CI tests | 5.x | MIT |
| PSScriptAnalyzer | Development/CI analysis | 1.25.x | MIT |

Runtime code detects missing YAML support and reports installation guidance. It never installs dependencies silently. CI installs development dependencies explicitly and should fail rather than silently selecting an incompatible major version.
