# Read-only unmanaged package observations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect WinGet-visible installed applications outside the current export as review-only observations without changing the active manifest or package state.

**Architecture:** Add a strict WinGet table parser and a read-only observation adapter beside the existing WinGet export adapter. Add a separate public exporter and JSON schema so unmanaged observations cannot be consumed by the existing manifest/planning path accidentally.

**Tech Stack:** PowerShell 7.4+, existing `System.Diagnostics.ProcessStartInfo` adapter, Pester 5.x in CI, JSON schema validation.

## Global Constraints

- Use absolute `pwsh.exe` and require PowerShell 7.4 or newer; never fall back to `powershell.exe`.
- Never install dependencies automatically.
- Never uninstall, elevate, reboot, add sources, modify drivers/BIOS/firmware, or execute arbitrary commands.
- Run only `winget list --disable-interactivity` for unmanaged observation collection; never pass source-agreement switches.
- Unknown, malformed, partial, stale, or ambiguous state remains visible and is never guessed.
- The unmanaged artifact is review-only and always uses `reviewStatus: pending`.
- Do not persist manager executable paths, raw stderr, usernames, or credentials.

---

### Task 1: Add parser and observation contract tests

**Files:**
- Modify: `tests/Contract/Manager.Tests.ps1`
- Create: `tests/Unit/UnmanagedObservations.Tests.ps1`

**Interfaces:**
- `ConvertFrom-WpaWingetList -Text <string>` returns an array for valid output, an empty array for a recognized empty table, and `$null` for unknown or malformed output.
- `Get-WpaWingetUnmanagedObservations -KnownIds <string[]>` returns a result with `status`, `observations`, and `warning` fields.

- [x] **Step 1: Write failing parser tests**

Add contract tests for these exact fixtures:

```powershell
$english = "Name                 Id                         Version  Available  Source`n---------------------  -------------------------  -------  ---------  ------`nAblaze Floorp         ARP\Machine\X64\Floorp     12.10.4             `n7-Zip                7zip.7zip                  25.01    26.02      winget"
$japanese = "名前                 ID                         バージョン  利用可能  ソース`n---------------------  -------------------------  --------  --------  ------`nAblaze Floorp         ARP\Machine\X64\Floorp     12.10.4                       `n7-Zip                7zip.7zip                  25.01     26.02     winget"
```

Assert that IDs, installed versions, blank source, and `winget` source are preserved. Add a recognized header with only a separator and assert `@(...).Count -eq 0`; add an unknown header and a malformed row and assert `$null`.

- [x] **Step 2: Run the parser tests and confirm failure**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Set-Location -LiteralPath '$PWD'; Invoke-Pester -Path ./tests/Contract/Manager.Tests.ps1,./tests/Unit/UnmanagedObservations.Tests.ps1 -Output Detailed"
```

Expected: the new parser command is unavailable and the new tests fail before implementation.

- [x] **Step 3: Add observation behavior tests**

Mock `Resolve-WpaManagerExecutable` and `Invoke-WpaProcess`. Return the fixture above for `list`, and assert that `KnownIds = @('7zip.7zip')` excludes 7-Zip, leaves the ARP row as `manual-mapping`, and never invokes arguments containing `--accept-source-agreements` or `--accept-package-agreements`. Add a failed-process fixture and assert no observations are returned.

### Task 2: Implement strict WinGet list observations

**Files:**
- Modify: `src/WinPkgAgent/Private/Adapters/Process.ps1`
- Modify: `src/WinPkgAgent/Private/Adapters/Winget.ps1`
- Test: `tests/Contract/Manager.Tests.ps1`

**Interfaces:**
- `ConvertFrom-WpaWingetList` is private and pure.
- `Get-WpaWingetUnmanagedObservations` is private and performs only one read-only process call.

- [x] **Step 1: Implement recognized-header and strict row parsing**

Recognize the exact English labels `Name`, `Id`, `Version`, `Available`, `Source` and Japanese labels `名前`, `ID`, `バージョン`, `利用可能`, `ソース`. Use the header only to establish the output contract, parse rows by strict two-or-more-space boundaries, handle long IDs whose final version token is separated by one space, require name/id/version, and reject any non-separator row that cannot be parsed. Return `$null` on uncertainty.

- [x] **Step 2: Implement the read-only observation adapter**

Add a `-NoTruncateOutput` switch to `Invoke-WpaProcess`; it must retain redaction while bypassing only the 4096-character diagnostic truncation. Resolve the verified executable, call `Invoke-WpaProcess -Arguments @('list','--disable-interactivity') -NoTruncateOutput`, parse stdout, and return `status='failed'` on unavailable/malformed output. Exclude case-insensitive known IDs. Set `actionability='manager-candidate'` only for IDs matching `^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$` with a non-empty source; otherwise set `actionability='manual-mapping'` and `reasonCode='UNMANAGED_ID_REQUIRES_MAPPING'`.

- [x] **Step 3: Run focused direct assertions**

Use PowerShell 7 to import the module, call the parser with English/Japanese/empty/malformed fixtures, and assert the exact result counts and classifications.

### Task 3: Add the separate review artifact and CLI surface

**Files:**
- Create: `src/WinPkgAgent/Public/Export-WpaUnmanagedCandidate.ps1`
- Create: `schemas/unmanaged-candidate.schema.json`
- Modify: `src/WinPkgAgent/WinPkgAgent.psm1`
- Modify: `src/WinPkgAgent/WinPkgAgent.psd1`
- Modify: `scripts/winpkg-agent.ps1`
- Modify: `tests/Unit/UnmanagedObservations.Tests.ps1`
- Modify: `tests/Integration/Cli.Tests.ps1`

**Interfaces:**
- `Export-WpaUnmanagedCandidate -InventoryPath <string> -OutputPath <string>` reads the inventory, invokes the observation adapter with inventory IDs, validates the result against `unmanaged-candidate.schema.json`, writes an atomic JSON review artifact, and returns `status`, `path`, and `count`.
- CLI command `unmanaged-candidate` maps `-InventoryPath` and `-OutputPath` to that public function.

- [x] **Step 1: Define the schema**

Require `schemaVersion=1`, `status`, `observedAt`, `inventoryStateHash`, `reviewStatus='pending'`, `warnings`, and `observations`. Require each observation to contain `displayName`, `observedId`, `installedVersion`, `availableVersion`, `source`, `actionability`, `reasonCode`, `reviewStatus`, and `detectedBy='winget-list'`. Allow only `manager-candidate` and `manual-mapping` actionability values.

- [x] **Step 2: Implement the exporter**

Read and validate the existing inventory, calculate its state hash, call the observation adapter, preserve failure/partial warnings, validate the review object, and write it only through `Write-WpaAtomicJson`. Never write an active manifest or approval artifact.

- [x] **Step 3: Wire the public command and CLI**

Add the public function to both module export lists, add `unmanaged-candidate` to the CLI `ValidateSet`, dispatch it, and add it to the expected command list test. Do not alter the existing `manifest`, `plan`, `approve`, or `invoke` paths.

- [x] **Step 4: Run unit, schema, and CLI tests**

Run the focused tests, `Test-Json` against a generated review artifact, and the CLI command with a fixture inventory. The fixture test must assert that no active manifest or approval file is created.

### Task 4: Live read-only verification and documentation

**Files:**
- Modify: `docs/usage.ja.md`
- Modify: `docs/usage.md`
- Modify: `docs/package-ownership.md`
- Modify: `.codex/tasks/package-migration.md`

- [x] **Step 1: Document the review-only command**

Document the absolute PowerShell 7 command:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File ./scripts/winpkg-agent.ps1 unmanaged-candidate -InventoryPath ./artifacts/migration-inventory.json -OutputPath ./artifacts/unmanaged-candidate.json
```

State that ARP/MSIX and source-less IDs remain manual mappings and cannot be approved automatically.

- [x] **Step 2: Run live read-only inventory and unmanaged observation**

Run inventory, export the existing pending manifest candidate, then run `unmanaged-candidate` under the user's PowerShell 7.4+ context. Confirm manager state, observation count, schema validation, and absence of mutation calls.

- [x] **Step 3: Review safety and diff**

Run AST parsing, `git diff --check`, search changed files for forbidden mutation additions, confirm no raw executable paths in artifacts, and confirm the unrelated main-worktree file is untouched.

- [x] **Step 4: Record evidence in Plane**

Add one concise verification comment to the existing WinPkgAgent task. Keep the item in the existing `In Progress` state because the project has no Review state; do not mark it Done or invoke approval.

### Task 5: Commit the verified implementation

**Files:**
- Commit only the changed source, tests, schemas, docs, and task-state files; keep generated artifacts ignored.

- [x] **Step 1: Run the repository-supported verification set**

Run the closest tests first, then schema/CLI checks, then the live read-only smoke command. Report the local Pester 3 vs repository Pester 5 limitation without installing dependencies.

- [x] **Step 2: Inspect status and diff**

Require a clean worktree except for intentionally ignored artifacts and no changes outside the worktree.

- [x] **Step 3: Commit**

```powershell
git add src tests schemas scripts docs .codex/tasks/package-migration.md
git commit -m "feat: observe unmanaged winget packages safely"
```
