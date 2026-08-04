# Contributing

## Before opening a change

Read the design and plan under `docs/superpowers/` (these files are normative for this repository). Keep changes small, explain the safety impact, and add tests for changed behavior. Do not add a package-manager mutation to a test.

## Local checks

Use PowerShell 7.4+. Install development dependencies explicitly in your environment; this project never installs them implicitly. Run schema/sample validation, module import, PSScriptAnalyzer, Pester, and the fixture-only CLI `-WhatIf` smoke test. If a check cannot run, report the exact command and reason.

## Pull requests

Describe the workflow stage affected, policy/reason-code changes, test evidence, and known limitations. Avoid personal names, local paths, secrets, and real package output. A reviewer must be able to see that no approval bypass, unsafe process invocation, or real package mutation was introduced.

## Dependency policy

Runtime dependency: `powershell-yaml` 0.4.12 (Apache-2.0). Development dependencies: Pester 5.x and PSScriptAnalyzer 1.25.x. Versions are explicit in CI; dependency updates require license and compatibility review.
