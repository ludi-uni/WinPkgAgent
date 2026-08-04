# Manager Executable Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make WinGet and Scoop discoverable and executable from non-interactive environments such as Codex when their user-level installations are not present on the inherited PATH.

**Architecture:** Add one private resolver that prefers PATH resolution and then checks only allow-listed, user-level manager locations. Availability checks, inventory, install, and upgrade calls will all use the resolved executable so detection cannot succeed while execution later fails. Resolved paths remain in memory and are not persisted in artifacts.

**Tech Stack:** PowerShell 7.4+, Pester 5.x, existing WinPkgAgent process adapter.

## Global Constraints

- Preserve the fail-closed inventory → plan → approval → apply → verify workflow.
- Never install dependencies, alter PATH persistently, elevate, or execute arbitrary commands.
- Keep manager paths allow-listed and do not persist raw host/user values.
- Approval remains interactive and human-only.

---

### Task 1: Add resolver regression coverage

**Files:**
- Modify: `tests/Contract/Manager.Tests.ps1`

**Interfaces:**
- Test `Resolve-WpaManagerExecutable` and the manager availability functions through controlled candidate paths.

- [ ] Add tests proving PATH resolution is preferred.
- [ ] Add tests proving a user Scoop shim is resolved when PATH lookup is unavailable.
- [ ] Add tests proving missing candidates remain unavailable.
- [ ] Run the focused tests and observe the expected failure before implementation.

### Task 2: Implement and integrate manager resolution

**Files:**
- Create: `src/WinPkgAgent/Private/Adapters/ExecutableResolution.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Winget.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Scoop.ps1`

**Interfaces:**
- `Resolve-WpaManagerExecutable -Manager winget|scoop` returns an executable path or `$null`.
- `Test-WpaWingetAvailable` and `Test-WpaScoopAvailable` use the resolver.
- Inventory and mutating manager adapter functions use the resolved executable.

- [ ] Implement allow-listed PATH and user-level fallback resolution.
- [ ] Route availability, inventory, install, and upgrade through the resolver.
- [ ] Preserve existing process argument arrays and safety gates.
- [ ] Run focused tests until green.

### Task 3: Document non-interactive environment behavior

**Files:**
- Modify: `README.ja.md`
- Modify: `docs/troubleshooting.md`

- [ ] Explain PATH-independent user shim discovery.
- [ ] Explain that persistent PATH changes and automatic manager installation are not performed.
- [ ] Add diagnostic commands for unresolved managers.

### Task 4: Verify integration

**Files:**
- No additional files.

- [ ] Run manager contract and inventory tests.
- [ ] Run build/static checks available in the repository.
- [ ] Run `Test-WpaEnvironment` and confirm the observed result is explained by resolver behavior.
- [ ] Review diff for secrets, unsafe paths, and unrelated changes.
