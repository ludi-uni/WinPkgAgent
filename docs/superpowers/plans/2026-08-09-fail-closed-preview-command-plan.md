# Fail-closed Preview Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-command `preview` CLI that creates and summarizes a trusted policy-scoped run while always stopping before human typed-digest approval.

**Architecture:** Extract private in-memory environment, inventory, and plan builders so one immutable policy/inventory snapshot drives the run. Refactor `New-WpaRun` into prepare and atomic publish phases, then add a CLI-only summary wrapper and exit-code mapping without adding a public PowerShell API or changing artifact schemas.

**Tech Stack:** PowerShell 7.4+, Pester 5.6.1, powershell-yaml 0.4.12, JSON Schema, PSScriptAnalyzer 1.25.0.

## Global Constraints

- Follow inventory → plan → human approval → apply → verify; `preview` implements only the first two stages.
- `preview` must never call approval functions, apply functions, mutation adapters, elevation, uninstall, source addition, reboot, driver, BIOS, UEFI, firmware, or arbitrary commands.
- A policy, environment, manifest, profile, inventory, fingerprint, path, or publication state that is unknown, partial, stale, ambiguous, invalid, or tampered must fail closed.
- An environment or inventory trust failure must publish no completed run; package-level policy blocks must remain in a reviewable completed run.
- The same parsed policy object and the same inventory snapshot must drive environment scope, plan evaluation, and persisted artifacts.
- Codex/Scoop policy must not probe WinGet; desktop policy must require every allowed manager to be ready and fully inventoried.
- Preserve the human-only interactive typed-digest approval boundary; do not add force switches, approval environment variables, or approval artifacts to `preview`.
- Preserve `New-WpaRun`'s public signature, the module export list, and all manifest/policy/inventory/plan/run schemas.
- Use absolute `C:\Program Files\PowerShell\7\pwsh.exe` for local verification; never use `powershell.exe` or mutate PATH.
- Tests must use mocks and fixtures and must not mutate real packages or install dependencies.
- Keep all generated artifacts inside the selected run directory and retain traversal/reparse-point checks.
- Do not stage or modify the pre-existing unrelated changes in `src/WinPkgAgent/Private/Adapters/Scoop.ps1` and `tests/Contract/Manager.Tests.ps1` as part of these tasks.

---

## File Map

- `src/WinPkgAgent/Private/Runtime/PolicyEnvironment.ps1`: build an environment result from an already parsed policy object.
- `src/WinPkgAgent/Private/Inventory/PolicyInventory.ps1`: build an inventory from an already parsed policy object.
- `src/WinPkgAgent/Private/Planning/PlanBuilder.ps1`: build and integrity-check a plan object without reading or writing files.
- `src/WinPkgAgent/Private/Workspace/RunPreparation.ps1`: snapshot and validate manifest, profile, policy, environment, inventory, and plan in memory.
- `src/WinPkgAgent/Private/Workspace/RunPublication.ps1`: publish a prepared run through an owned staging directory and preserve staging evidence on failure.
- `src/WinPkgAgent/Private/Schema/DataFiles.ps1`: parse exact YAML text so validated content and persisted content cannot drift.
- `src/WinPkgAgent/Private/Workspace.ps1`: retain public run functions while delegating `New-WpaRun` to prepare/publish helpers.
- `src/WinPkgAgent/Public/Test-WpaEnvironment.ps1`: keep the public file-based API and delegate to the private builder.
- `src/WinPkgAgent/Public/Get-WpaInventory.ps1`: keep the public file-based API and delegate to the private builder.
- `src/WinPkgAgent/Public/New-WpaPlan.ps1`: keep the public file-based API and delegate plan construction to the private builder.
- `scripts/Private/Preview.ps1`: orchestrate `New-WpaRun`, validate the generated plan, and return one CLI summary object.
- `scripts/Private/ExitCode.ps1`: map blocked previews to exit code 2 without changing codes 3–5.
- `scripts/winpkg-agent.ps1`: expose the CLI-only `preview` command.
- `tests/Unit/Environment.Tests.ps1`, `tests/Unit/Inventory.Tests.ps1`, `tests/Unit/Planning.Tests.ps1`, `tests/Unit/Workspace.Tests.ps1`, `tests/Unit/ResultSchema.Tests.ps1`: focused private/public boundary tests.
- `tests/Integration/Cli.Tests.ps1`: preview routing, summary, no-approval, and exit-code coverage.
- `README.md`, `README.ja.md`, `docs/usage.md`, `docs/usage.ja.md`, `docs/troubleshooting.md`: user-facing workflow and failure guidance.
- `.github/workflows/ci.yml`: fixture-only `preview -WhatIf` smoke check.

---

### Task 1: Build environment and inventory from one parsed policy

**Files:**
- Create: `src/WinPkgAgent/Private/Runtime/PolicyEnvironment.ps1`
- Create: `src/WinPkgAgent/Private/Inventory/PolicyInventory.ps1`
- Modify: `src/WinPkgAgent/Public/Test-WpaEnvironment.ps1:1-28`
- Modify: `src/WinPkgAgent/Public/Get-WpaInventory.ps1:1-15`
- Test: `tests/Unit/Environment.Tests.ps1`
- Test: `tests/Unit/Inventory.Tests.ps1`

**Interfaces:**
- Consumes: validated policy objects with `allowedManagers` and optional `runtime.powershellPath`.
- Produces: `Test-WpaEnvironmentForPolicy([object]$Policy,[string]$PowerShellPath)` and `Get-WpaInventoryForPolicy([object]$Policy)` for Task 3.

- [ ] **Step 1: Add failing environment policy-object tests**

Inside the existing `InModuleScope WinPkgAgent` block in `tests/Unit/Environment.Tests.ps1`, add:

```powershell
It 'probes only managers allowed by the parsed policy object' {
    $policy = [pscustomobject]@{ allowedManagers=@('scoop'); runtime=$null }
    Mock Get-WpaPowerShellRuntimeInfo { [pscustomobject]@{Compatible=$true;Version='7.4.0';Source='current';Path=$null;ReasonCode=$null;Reason=$null;Fingerprint=$null} }
    Mock ConvertTo-WpaPowerShellRuntimeArtifact { [pscustomobject]@{compatible=$true;version='7.4.0'} }
    Mock Test-WpaScoopAvailable { $true }
    Mock Test-WpaWingetAvailable { throw 'winget must not be probed' }
    Mock Get-Module { [pscustomobject]@{Version=[version]'0.4.12'} } -ParameterFilter { $ListAvailable }

    $result = Test-WpaEnvironmentForPolicy -Policy $policy

    $result.ready | Should -BeTrue
    $result.managers.scoop | Should -BeTrue
    $result.managers.winget | Should -BeFalse
    Should -Invoke Test-WpaWingetAvailable -Times 0 -Exactly
}
```

- [ ] **Step 2: Run the environment test and verify RED**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Environment.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: FAIL because `Test-WpaEnvironmentForPolicy` is not defined.

- [ ] **Step 3: Add the private environment builder and delegate the public function**

Create `PolicyEnvironment.ps1` with this function boundary:

```powershell
function Test-WpaEnvironmentForPolicy {
    [CmdletBinding()]
    param([AllowNull()][object]$Policy,[string]$PowerShellPath)

    $configuredPath = $PowerShellPath
    $allowedManagers = if($Policy){ @($Policy.allowedManagers | ForEach-Object {[string]$_}) } else { @('winget','scoop') }
    if($Policy -and -not $configuredPath){
        $runtime = Get-WpaPropertyValue $Policy 'runtime' $null
        if($runtime){ $configuredPath = [string](Get-WpaPropertyValue $runtime 'powershellPath' $null) }
    }
    $runtimeInfo = Get-WpaPowerShellRuntimeInfo -PowerShellPath $configuredPath
    $runtimeArtifact = ConvertTo-WpaPowerShellRuntimeArtifact -Runtime $runtimeInfo
    $winget = if('winget' -in $allowedManagers){ [bool](Test-WpaWingetAvailable) } else { $false }
    $scoop = if('scoop' -in $allowedManagers){ [bool](Test-WpaScoopAvailable) } else { $false }
    $managerReady = if($Policy){
        $allAllowedReady = $allowedManagers.Count -gt 0
        foreach($manager in $allowedManagers){
            if(($manager -eq 'winget' -and -not $winget) -or ($manager -eq 'scoop' -and -not $scoop) -or $manager -notin @('winget','scoop')){ $allAllowedReady=$false }
        }
        $allAllowedReady
    } else {
        $winget -or $scoop
    }
    [pscustomobject]@{
        schemaVersion=1; environmentId=(Get-WpaEnvironmentId); powerShellVersion=$runtimeArtifact.version
        powerShellSupported=[bool]$runtimeArtifact.compatible; powershell=$runtimeArtifact
        yamlDependencyAvailable=[bool](Get-Module -ListAvailable powershell-yaml | Where-Object Version -GE ([version]'0.4.12'))
        managers=[pscustomobject]@{winget=$winget;scoop=$scoop}
        ready=([bool]$runtimeArtifact.compatible -and $managerReady)
    }
}
```

Change `Test-WpaEnvironment` to read and schema-check `-PolicyPath` once, then return `Test-WpaEnvironmentForPolicy -Policy $policy -PowerShellPath $PowerShellPath`. Preserve the existing no-policy compatibility behavior by passing `$null`.

- [ ] **Step 4: Add failing inventory policy-object tests**

Inside `tests/Unit/Inventory.Tests.ps1`, add:

```powershell
It 'collects inventory from the same parsed policy object' {
    $policy = [pscustomobject]@{ allowedManagers=@('scoop') }
    Mock Test-WpaDataSchema { $true }
    Mock Get-WpaObjectHash { 'a' * 64 }
    Mock Get-WpaInventoryAggregate { param($Managers,$PolicyHash) [pscustomobject]@{status='success';managerScope=@($Managers);policyHash=$PolicyHash} }

    $result = Get-WpaInventoryForPolicy -Policy $policy

    $result.status | Should -Be 'success'
    Should -Invoke Get-WpaInventoryAggregate -ParameterFilter { @($Managers) -join ',' -eq 'scoop' -and $PolicyHash -eq ('a' * 64) } -Times 1 -Exactly
}
```

- [ ] **Step 5: Run the inventory test and verify RED**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Inventory.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: FAIL because `Get-WpaInventoryForPolicy` is not defined.

- [ ] **Step 6: Add the private inventory builder and delegate the public function**

Create `PolicyInventory.ps1`:

```powershell
function Get-WpaInventoryForPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Policy)
    Test-WpaDataSchema -Data $Policy -SchemaName policy | Out-Null
    $policyHash = Get-WpaObjectHash -InputObject $Policy
    $inventory = Get-WpaInventoryAggregate -Managers @($Policy.allowedManagers | ForEach-Object {[string]$_}) -PolicyHash $policyHash
    Test-WpaDataSchema -Data $inventory -SchemaName inventory | Out-Null
    return $inventory
}
```

Change `Get-WpaInventory` to read `Read-WpaPolicyFile -Path $PolicyPath`, call `Get-WpaInventoryForPolicy`, preserve `ShouldProcess`, and write only when `-OutputPath` is supplied.

- [ ] **Step 7: Run both focused suites and verify GREEN**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path @('./tests/Unit/Environment.Tests.ps1','./tests/Unit/Inventory.Tests.ps1') -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: PASS with zero failures.

- [ ] **Step 8: Commit Task 1 files only**

```powershell
git add src/WinPkgAgent/Private/Runtime/PolicyEnvironment.ps1 src/WinPkgAgent/Private/Inventory/PolicyInventory.ps1 src/WinPkgAgent/Public/Test-WpaEnvironment.ps1 src/WinPkgAgent/Public/Get-WpaInventory.ps1 tests/Unit/Environment.Tests.ps1 tests/Unit/Inventory.Tests.ps1
git commit -m "refactor: share policy scoped probes"
```

---

### Task 2: Extract a file-free plan object builder

**Files:**
- Create: `src/WinPkgAgent/Private/Planning/PlanBuilder.ps1`
- Modify: `src/WinPkgAgent/Public/New-WpaPlan.ps1:1-35`
- Test: `tests/Unit/Planning.Tests.ps1`

**Interfaces:**
- Consumes: resolved manifest object, validated policy object, schema-v2 inventory object, and `datetimeoffset`.
- Produces: `New-WpaPlanObject([object]$Manifest,[object]$Policy,[object]$Inventory,[datetimeoffset]$Now)` for Task 3.

- [ ] **Step 1: Add a failing pure-builder test**

Add to `tests/Unit/Planning.Tests.ps1`:

```powershell
It 'builds a plan object without reading or writing files' {
    $policy.allowedManagers=@('scoop')
    $manifest=[pscustomobject]@{schemaVersion=1;profiles=@();packages=@([pscustomobject]@{name='tool';manager='scoop';id='tool';state='present';version='latest';source='main'})}
    $fingerprint=[pscustomobject]@{manager='scoop';signatureStatus='not-applicable';aclAssessment='trusted'}
    $inventory=[pscustomobject]@{schemaVersion=2;policyHash=(Get-WpaObjectHash $policy);managerScope=@('scoop');environment=@{id='env'};status='success';managers=@([pscustomobject]@{manager='scoop';status='success';fingerprint=$fingerprint});packages=@();warnings=@();collectedAt='2026-01-01T00:00:00Z'}
    Mock Read-WpaJsonFile { throw 'file reads are forbidden' }
    Mock Write-WpaAtomicJson { throw 'file writes are forbidden' }

    $plan=New-WpaPlanObject -Manifest $manifest -Policy $policy -Inventory $inventory -Now ([datetimeoffset]'2026-01-01T00:00:00Z')

    $plan.environmentId | Should -Be 'env'
    $plan.policyHash | Should -Be (Get-WpaObjectHash $policy)
    $plan.planHash | Should -Match '^[a-f0-9]{64}$'
    Should -Invoke Read-WpaJsonFile -Times 0 -Exactly
    Should -Invoke Write-WpaAtomicJson -Times 0 -Exactly
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Planning.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: FAIL because `New-WpaPlanObject` is not defined.

- [ ] **Step 3: Move semantic plan construction into `New-WpaPlanObject`**

Create `PlanBuilder.ps1` with this exact signature:

```powershell
function New-WpaPlanObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Manifest,
        [Parameter(Mandatory)][object]$Policy,
        [Parameter(Mandatory)][object]$Inventory,
        [datetimeoffset]$Now=[datetimeoffset]::UtcNow
    )
```

Move the existing policy-hash/manager-scope checks, fingerprint checks, `Get-WpaPlanEvaluation`, timestamp generation, content hash, plan hash, action-set assertion, and plan schema validation from `New-WpaPlan` into this function. Return the completed plan object and perform no file I/O.

Reduce `New-WpaPlan` to:

```powershell
$manifest=Read-WpaManifestResolved $ManifestPath
Test-WpaManifestObject $manifest | Out-Null
Test-WpaDataSchema $manifest manifest | Out-Null
$policy=Read-WpaPolicyFile $PolicyPath
Test-WpaDataSchema $policy policy | Out-Null
$inventory=ConvertTo-WpaInventoryBoundary (Read-WpaJsonFile $InventoryPath)
Test-WpaDataSchema $inventory inventory | Out-Null
$plan=New-WpaPlanObject -Manifest $manifest -Policy $policy -Inventory $inventory -Now $Now
```

Keep the existing `ShouldProcess` writes and `ConvertTo-WpaPlanMarkdown` unchanged.

- [ ] **Step 4: Run planning tests and verify GREEN**

Run the command from Step 2.

Expected: all planning tests PASS, including policy-hash and fingerprint failures.

- [ ] **Step 5: Commit Task 2 files only**

```powershell
git add src/WinPkgAgent/Private/Planning/PlanBuilder.ps1 src/WinPkgAgent/Public/New-WpaPlan.ps1 tests/Unit/Planning.Tests.ps1
git commit -m "refactor: extract in-memory plan builder"
```

---

### Task 3: Prepare one immutable run snapshot before filesystem publication

**Files:**
- Modify: `src/WinPkgAgent/Private/Schema/DataFiles.ps1:24-32`
- Create: `src/WinPkgAgent/Private/Workspace/RunPreparation.ps1`
- Test: `tests/Unit/Workspace.Tests.ps1`

**Interfaces:**
- Consumes: Task 1's `Test-WpaEnvironmentForPolicy` and `Get-WpaInventoryForPolicy`; Task 2's `New-WpaPlanObject`.
- Produces: `New-WpaRunPreparation([string]$ManifestPath,[string]$PolicyPath,[string]$RunId,[datetimeoffset]$Now)` returning `manifestText`, `policyText`, `profiles`, `manifest`, `policy`, `inventory`, `plan`, and `run`.

- [ ] **Step 1: Add failing tests for trust failure and exact policy reuse**

Add to `tests/Unit/Workspace.Tests.ps1`:

```powershell
It 'stops preparation before inventory when the policy-scoped environment is not ready' {
    Mock Read-WpaRunInputSnapshot { [pscustomobject]@{manifest=[pscustomobject]@{packages=@()};policy=[pscustomobject]@{allowedManagers=@('scoop')}} }
    Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$false} }
    Mock Get-WpaInventoryForPolicy { throw 'inventory must not run' }

    { New-WpaRunPreparation -ManifestPath manifest.yaml -PolicyPath policy.yaml -RunId '20260809-010203-aabbccdd' } | Should -Throw 'PREVIEW_ENVIRONMENT_NOT_READY'
    Should -Invoke Get-WpaInventoryForPolicy -Times 0 -Exactly
}

It 'rejects partial inventory before producing a plan' {
    $policy=[pscustomobject]@{allowedManagers=@('scoop')}
    Mock Read-WpaRunInputSnapshot { [pscustomobject]@{manifest=[pscustomobject]@{packages=@()};policy=$policy;manifestText='packages: []';policyText='allowedManagers: [scoop]';profiles=@()} }
    Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
    Mock Get-WpaInventoryForPolicy { [pscustomobject]@{status='partial'} }
    Mock New-WpaPlanObject { throw 'plan must not run' }

    { New-WpaRunPreparation -ManifestPath manifest.yaml -PolicyPath policy.yaml -RunId '20260809-010203-aabbccdd' } | Should -Throw 'PREVIEW_INVENTORY_NOT_TRUSTED: partial'
    Should -Invoke New-WpaPlanObject -Times 0 -Exactly
}
```

- [ ] **Step 2: Run workspace tests and verify RED**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Workspace.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: FAIL because the preparation functions are undefined.

- [ ] **Step 3: Parse exact YAML text instead of rereading mutable files**

Add to `DataFiles.ps1`:

```powershell
function ConvertFrom-WpaYamlText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    $yamlModule=Get-Module -ListAvailable -Name powershell-yaml | Where-Object Version -GE ([version]'0.4.12') | Select-Object -First 1
    if(-not $yamlModule){throw 'powershell-yaml 0.4.12 or newer is required. Install it explicitly after reviewing the dependency documentation.'}
    Import-Module $yamlModule.Path -ErrorAction Stop
    try { ConvertFrom-Yaml -Yaml $Text -Ordered } catch { throw "Invalid YAML file: $($_.Exception.Message)" }
}
```

Change `Read-WpaYamlFile` to call `ConvertFrom-WpaYamlText -Text (Read-WpaTextFile -Path $Path)`. This preserves public behavior while allowing snapshots to parse the exact bytes later persisted.

- [ ] **Step 4: Implement input snapshot and preparation helpers**

In `RunPreparation.ps1`, implement:

```powershell
function Read-WpaRunInputSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$PolicyPath)
```

The function must read each manifest, policy, and selected profile text exactly once with `Read-WpaTextFile`, parse each with `ConvertFrom-WpaYamlText`, reject invalid profile names and nested profiles, aggregate profile packages before manifest packages, and return:

```powershell
[pscustomobject]@{
    manifestText=$manifestText
    policyText=$policyText
    profiles=@($profileSnapshots)
    manifest=[pscustomobject]@{schemaVersion=$manifestData.schemaVersion;profiles=@($profileNames);packages=@($packages)}
    policy=$policy
}
```

Each profile snapshot is a `[pscustomobject]` with string properties `name` and `text`; `name` has already matched `^[a-z0-9][a-z0-9-]{0,31}$`, and `text` is the exact YAML text. Validate the resolved manifest with `Test-WpaManifestObject` and manifest schema, and validate policy with `Test-WpaPolicyObject` and policy schema before returning.

Implement preparation:

```powershell
function New-WpaRunPreparation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$PolicyPath,[Parameter(Mandatory)][string]$RunId,[datetimeoffset]$Now=[datetimeoffset]::UtcNow)
    $snapshot=Read-WpaRunInputSnapshot -ManifestPath $ManifestPath -PolicyPath $PolicyPath
    $environment=Test-WpaEnvironmentForPolicy -Policy $snapshot.policy
    if(-not $environment.ready){throw 'PREVIEW_ENVIRONMENT_NOT_READY'}
    $inventory=Get-WpaInventoryForPolicy -Policy $snapshot.policy
    if([string]$inventory.status -ne 'success'){throw "PREVIEW_INVENTORY_NOT_TRUSTED: $($inventory.status)"}
    $plan=New-WpaPlanObject -Manifest $snapshot.manifest -Policy $snapshot.policy -Inventory $inventory -Now $Now
    if($RunId -notmatch '^[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'){throw 'RUN_ID_INVALID'}
    $run=[pscustomobject][ordered]@{
        schemaVersion=1;runId=$RunId;createdAt=$Now.ToUniversalTime().ToString('o')
        manifestHash=$plan.manifestHash;policyHash=$plan.policyHash
        manifestPath='manifest.yaml';policyPath='policy.yaml';inventoryPath='inventory.json';planPath='plan.json'
        approvalPath='approval.json';applyResultPath='apply-result.json';verifyResultPath='verify-result.json'
        journalPath='journal.json';summaryPath='summary.md';currentStage='planned'
    }
    return [pscustomobject]@{
        manifestText=$snapshot.manifestText;policyText=$snapshot.policyText;profiles=@($snapshot.profiles)
        manifest=$snapshot.manifest;policy=$snapshot.policy;inventory=$inventory;plan=$plan;run=$run
    }
}
```

Do not create directories or write files in this function.

- [ ] **Step 5: Add and run the successful preparation test**

Add this test:

```powershell
It 'reuses the exact policy and inventory objects while preparing a run' {
    $policy=[pscustomobject]@{allowedManagers=@('scoop')}
    $manifest=[pscustomobject]@{schemaVersion=1;profiles=@();packages=@()}
    $snapshot=[pscustomobject]@{manifest=$manifest;policy=$policy;manifestText='packages: []';policyText='allowedManagers: [scoop]';profiles=@()}
    $inventory=[pscustomobject]@{status='success'}
    $plan=[pscustomobject]@{manifestHash='manifest-hash';policyHash='policy-hash'}
    Mock Read-WpaRunInputSnapshot { $snapshot }
    Mock Test-WpaEnvironmentForPolicy { [pscustomobject]@{ready=$true} }
    Mock Get-WpaInventoryForPolicy { param($Policy) if(-not [object]::ReferenceEquals($Policy,$policy)){throw 'policy object drift'}; $inventory }
    Mock New-WpaPlanObject { param($Manifest,$Policy,$Inventory) if(-not [object]::ReferenceEquals($Policy,$policy) -or -not [object]::ReferenceEquals($Inventory,$inventory)){throw 'snapshot drift'}; $plan }

    $result=New-WpaRunPreparation -ManifestPath manifest.yaml -PolicyPath policy.yaml -RunId '20260809-010203-aabbccdd' -Now ([datetimeoffset]'2026-08-09T01:02:03Z')

    [object]::ReferenceEquals($result.inventory,$inventory) | Should -BeTrue
    [object]::ReferenceEquals($result.plan,$plan) | Should -BeTrue
    Should -Invoke Get-WpaInventoryForPolicy -Times 1 -Exactly
    Should -Invoke New-WpaPlanObject -Times 1 -Exactly
}
```

Run the command from Step 2.

Expected: all workspace preparation tests PASS and no TestDrive workspace is created.

- [ ] **Step 6: Commit Task 3 files only**

```powershell
git add src/WinPkgAgent/Private/Schema/DataFiles.ps1 src/WinPkgAgent/Private/Workspace/RunPreparation.ps1 tests/Unit/Workspace.Tests.ps1
git commit -m "feat: prepare trusted run snapshots"
```

---

### Task 4: Publish prepared runs atomically with preserved failure evidence

> Approved design amendment (2026-08-09): path-based cleanup cannot prove object identity across a same-user replacement race. After staging creation, failure handling preserves staging and throws `PREVIEW_STAGING_PRESERVED`. Successful publication may use narrowly scoped private Windows handle interop to rename the owned staging-directory object; unknown or replacement objects are never removed or published.

> Human-approved completion amendment (2026-08-09): create an exclusive invocation-owned publication guard beside staging before the directory rename. After the exact owned directory reaches its canonical run path, rename that same guard handle to `.wpa-publication-pending`, validate the final owned contents, and rename the exact marker handle to `.wpa-publication-complete`. Readers reject either the sibling guard or the in-run pending marker before reading metadata. On evidence-quarantine failure, one of those pending names remains and no evidence is deleted.

**Files:**
- Create: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1`
- Modify: `src/WinPkgAgent/Private/Workspace.ps1:1-42`
- Test: `tests/Unit/Workspace.Tests.ps1`

**Interfaces:**
- Consumes: Task 3's preparation object and existing fixed artifact helpers.
- Produces: `Publish-WpaPreparedRun([object]$Preparation,[string]$WorkspacePath)`; `New-WpaRun` continues returning the unchanged run schema object.

- [ ] **Step 1: Add failing publication and failure-preservation tests**

Create the fixture at the start of a nested `Context 'prepared run publication'`:

```powershell
BeforeEach {
    $script:preparedRun=[pscustomobject][ordered]@{
        schemaVersion=1;runId='20260809-010203-aabbccdd';createdAt='2026-08-09T01:02:03.0000000Z'
        manifestHash=('a'*64);policyHash=('b'*64);manifestPath='manifest.yaml';policyPath='policy.yaml'
        inventoryPath='inventory.json';planPath='plan.json';approvalPath='approval.json'
        applyResultPath='apply-result.json';verifyResultPath='verify-result.json';journalPath='journal.json'
        summaryPath='summary.md';currentStage='planned'
    }
    $script:preparation=[pscustomobject]@{
        manifestText="schemaVersion: 1`npackages: []`n";policyText="schemaVersion: 1`n"
        profiles=@();inventory=[pscustomobject]@{status='success'}
        plan=[pscustomobject]@{actions=@();blockedOperations=@();warnings=@();planHash=('c'*64)}
        run=$script:preparedRun
    }
    Mock Test-WpaDataSchema { $true }
    Mock Assert-WpaPlanActionSet { $true }
    Mock Assert-WpaPlanIntegrity { $true }
}
```

Then add these observable cases:

```powershell
It 'publishes a complete run only after preparation succeeds' {
    Mock New-WpaRunPreparation { $script:preparation }
    $workspace=Join-Path $TestDrive 'workspace'
    $run=New-WpaRun -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $workspace -Now ([datetimeoffset]'2026-08-08T01:02:03Z')
    $final=Join-Path $workspace "runs/$($run.runId)"
    Test-Path (Join-Path $final 'run.json') | Should -BeTrue
    Test-Path (Join-Path $final 'approval.json') | Should -BeFalse
    Get-ChildItem (Join-Path $workspace 'runs') -Directory -Filter '.staging-*' | Should -BeNullOrEmpty
}

It 'preserves staging evidence when publication fails' {
    Mock New-WpaRunPreparation { $script:preparation }
    Mock Write-WpaAtomicJson { throw 'simulated publication failure' } -ParameterFilter { $Path -like '*plan.json' }
    $workspace=Join-Path $TestDrive 'workspace-failure'
    { New-WpaRun -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $workspace } | Should -Throw 'PREVIEW_STAGING_PRESERVED'
    @(Get-ChildItem (Join-Path $workspace 'runs') -Directory -Filter '.staging-*').Count | Should -Be 1
    Should -Invoke Remove-Item -Times 0 -Exactly
}
```

- [ ] **Step 2: Run workspace tests and verify RED**

Run the Task 3 focused workspace command.

Expected: publication tests FAIL because the current implementation creates the final run directly and lacks handle-bound staging publication and failure preservation.

- [ ] **Step 3: Implement guarded staging publication**

Create `RunPublication.ps1` with:

```powershell
function Publish-WpaPreparedRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Preparation,[Parameter(Mandatory)][string]$WorkspacePath)
```

Resolve and ancestor-check the workspace exactly as the current `New-WpaRun` does. Set `$runsPath`, `$finalPath`, and `$stagingPath=Join-Path $runsPath ('.staging-'+$Preparation.run.runId)`. Reject existing final/staging paths and any reparse-point ancestor. Acquire the staging directory atomically and retain a private handle that identifies the exact owned directory object; lexical path/marker equality is not sufficient ownership proof.

Write fixed artifacts from the preparation object:

```powershell
Write-WpaAtomicText (Get-WpaRunArtifactPath $stagingPath manifest) $Preparation.manifestText
Write-WpaAtomicText (Get-WpaRunArtifactPath $stagingPath policy) $Preparation.policyText
Write-WpaAtomicJson (Get-WpaRunArtifactPath $stagingPath inventory) $Preparation.inventory
Write-WpaAtomicJson (Get-WpaRunArtifactPath $stagingPath plan) $Preparation.plan
Write-WpaAtomicText (Get-WpaRunArtifactPath $stagingPath planMarkdown) (ConvertTo-WpaPlanMarkdown $Preparation.plan)
Write-WpaAtomicJson (Get-WpaRunArtifactPath $stagingPath run) $Preparation.run
```

For each profile snapshot, validate its name again, create only `profiles/<name>.yaml` beneath staging, reject reparse points, and write its exact text. Validate the staged run with `Read-WpaRun`, plan schema, `Assert-WpaPlanActionSet`, and `Assert-WpaPlanIntegrity`, then use narrowly scoped private Windows handle interop to rename that same owned directory object atomically to `$finalPath`. Never publish a replacement object found only by path.

In `catch`, if staging creation began, close only handles owned by this invocation, preserve staging evidence without any path-based delete/remove, and throw exactly `PREVIEW_STAGING_PRESERVED`. Do not include raw paths or command diagnostics. Before staging creation, rethrow the original sanitized validation/path error.

- [ ] **Step 4: Refactor `New-WpaRun` to delegate without changing its signature**

Keep its existing parameters. Generate the run ID before `ShouldProcess`; on `-WhatIf`, return only `{runPath=<final>;whatIf=$true}` without environment/manager probes. Otherwise call:

```powershell
$preparation=New-WpaRunPreparation -ManifestPath $ManifestPath -PolicyPath $PolicyPath -Now $Now -RunId $runId
Publish-WpaPreparedRun -Preparation $preparation -WorkspacePath $workspace | Out-Null
return $preparation.run
```

The private preparation function already takes mandatory `-RunId` from Task 3, so metadata and final path use the same ID. Leave `Get-WpaRun`, `Show-WpaRun`, `Approve-WpaRun`, and `Invoke-WpaRun` unchanged.

- [ ] **Step 5: Run workspace and planning tests and verify GREEN**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path @('./tests/Unit/Workspace.Tests.ps1','./tests/Unit/Planning.Tests.ps1') -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: PASS; no approval/apply artifacts exist in generated runs.

- [ ] **Step 6: Commit Task 4 files only**

```powershell
git add src/WinPkgAgent/Private/Workspace/RunPublication.ps1 src/WinPkgAgent/Private/Workspace.ps1 tests/Unit/Workspace.Tests.ps1
git commit -m "feat: publish runs through guarded staging"
```

---

### Task 5: Add the CLI-only preview summary and exit code

**Files:**
- Create: `scripts/Private/Preview.ps1`
- Modify: `scripts/Private/ExitCode.ps1:1-11`
- Modify: `scripts/winpkg-agent.ps1:1-42`
- Modify: `tests/Unit/ResultSchema.Tests.ps1`
- Modify: `tests/Integration/Cli.Tests.ps1`

**Interfaces:**
- Consumes: unchanged public `New-WpaRun`, `Test-WpaPlan`, and fixed `plan.json` path.
- Produces: one summary object with `status`, `runId`, `runPath`, `actionCount`, `blockedCount`, `warningCount`, `blockedReasons`, and `nextCommand`.

- [ ] **Step 1: Add failing CLI summary and exit-code tests**

Dot-source `scripts/Private/Preview.ps1` in the integration test setup, then add:

```powershell
It 'maps a blocked preview to exit code two' {
    . (Join-Path $root 'scripts/Private/ExitCode.ps1')
    Get-WpaCliExitCode -Command preview -Result ([pscustomobject]@{status='blocked';blockedCount=1}) | Should -Be 2
}

It 'summarizes blocked reasons without invoking approval or apply' {
    Mock New-WpaRun { [pscustomobject]@{runId='20260809-010203-aabbccdd'} }
    Mock Test-WpaPlan { [pscustomobject]@{valid=$true;errors=@()} }
    Mock Get-Content { '{"actions":[],"blockedOperations":[{"manager":"winget","id":"Vendor.Tool","reasonCode":"MANAGER_NOT_ALLOWED","reason":"manager is not allowed"}],"warnings":[]}' }
    Mock Approve-WpaRun { throw 'approval must not run' }
    Mock Invoke-WpaRun { throw 'apply must not run' }

    $result=Invoke-WpaCliPreview -ManifestPath manifest.yaml -PolicyPath policy.yaml -WorkspacePath $TestDrive

    $result.status | Should -Be 'blocked'
    $result.blockedCount | Should -Be 1
    $result.blockedReasons[0].reasonCode | Should -Be 'MANAGER_NOT_ALLOWED'
    $result.nextCommand | Should -Match 'approve-run'
    Should -Invoke Approve-WpaRun -Times 0 -Exactly
    Should -Invoke Invoke-WpaRun -Times 0 -Exactly
}
```

- [ ] **Step 2: Run CLI-focused tests and verify RED**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path @('./tests/Unit/ResultSchema.Tests.ps1','./tests/Integration/Cli.Tests.ps1') -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: FAIL because `preview` and `Invoke-WpaCliPreview` do not exist.

- [ ] **Step 3: Implement the private CLI preview wrapper**

Create `Preview.ps1` with:

```powershell
function ConvertTo-WpaCliSingleQuotedLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'","''") + "'"
}

function Invoke-WpaCliPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$PolicyPath,[string]$WorkspacePath='./.wpa',[switch]$WhatIf)
    $workspace=[IO.Path]::GetFullPath($(if($WorkspacePath){$WorkspacePath}else{'./.wpa'}))
    $run=New-WpaRun -ManifestPath $ManifestPath -PolicyPath $PolicyPath -WorkspacePath $workspace -WhatIf:$WhatIf
    if($WhatIf){
        return [pscustomobject]@{status='what-if';runId=$null;runPath=$run.runPath;actionCount=0;blockedCount=0;warningCount=0;blockedReasons=@();nextCommand=$null}
    }
    $runPath=Join-Path (Join-Path $workspace 'runs') $run.runId
    $planPath=Join-Path $runPath 'plan.json'
    $validation=Test-WpaPlan -PlanPath $planPath
    if(-not $validation.valid){throw ('PREVIEW_PLAN_INVALID: '+($validation.errors -join '; '))}
    $plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 100
    $blocked=@($plan.blockedOperations)
    $status=if($blocked.Count -gt 0){'blocked'}else{'ready'}
    $next="pwsh ./scripts/winpkg-agent.ps1 approve-run -RunPath $(ConvertTo-WpaCliSingleQuotedLiteral $runPath)"
    [pscustomobject]@{
        status=$status;runId=$run.runId;runPath=$runPath;actionCount=@($plan.actions).Count
        blockedCount=$blocked.Count;warningCount=@($plan.warnings).Count
        blockedReasons=@($blocked | ForEach-Object {[pscustomobject]@{manager=$_.manager;id=$_.id;reasonCode=$_.reasonCode;reason=$_.reason}})
        nextCommand=$next
    }
}
```

- [ ] **Step 4: Route the CLI and exit codes**

Dot-source `scripts/Private/Preview.ps1` beside `ExitCode.ps1`. Add `preview` to the command `ValidateSet` and add this switch branch:

```powershell
preview { Invoke-WpaCliPreview -ManifestPath $ManifestPath -PolicyPath $PolicyPath -WorkspacePath $WorkspacePath -WhatIf:$WhatIf }
```

Add before invoke mappings in `Get-WpaCliExitCode`:

```powershell
if($Command -eq 'preview' -and [int]$Result.blockedCount -gt 0){return 2}
```

Do not add `preview` to either module export list.

- [ ] **Step 5: Run CLI-focused tests and verify GREEN**

Run the command from Step 2.

Expected: PASS; existing invoke mappings remain 3, 4, and 5.

- [ ] **Step 6: Commit Task 5 files only**

```powershell
git add scripts/Private/Preview.ps1 scripts/Private/ExitCode.ps1 scripts/winpkg-agent.ps1 tests/Unit/ResultSchema.Tests.ps1 tests/Integration/Cli.Tests.ps1
git commit -m "feat: add fail-closed preview CLI"
```

---

### Task 6: Document preview and add fixture-only CI smoke coverage

**Files:**
- Modify: `README.md`
- Modify: `README.ja.md`
- Modify: `docs/usage.md`
- Modify: `docs/usage.ja.md`
- Modify: `docs/troubleshooting.md`
- Modify: `.github/workflows/ci.yml`
- Test: `tests/Integration/Cli.Tests.ps1`

**Interfaces:**
- Consumes: Task 5's CLI syntax, summary fields, and exit codes.
- Produces: documented Codex/Scoop and desktop preview workflows plus a no-artifact CI smoke gate.

- [ ] **Step 1: Add a failing documentation contract test**

Extend the existing documentation aggregation test in `tests/Integration/Cli.Tests.ps1` with:

```powershell
$docs | Should -Match 'winpkg-agent\.ps1 preview[\s\S]*policy\.codex\.yaml'
$docs | Should -Match 'preview[\s\S]*policy\.(desktop|default)\.yaml'
$docs | Should -Match 'blockedReasons'
$docs | Should -Match 'exit code 2|終了コード.?2'
$docs | Should -Match 'approve-run[\s\S]*invoke-run[\s\S]*WhatIf'
```

- [ ] **Step 2: Run the integration test and verify RED**

Run the CLI-focused command from Task 5 Step 2.

Expected: FAIL because preview documentation is absent.

- [ ] **Step 3: Add concise English and Japanese workflow documentation**

Document both policy examples:

```powershell
pwsh ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.codex.yaml -WorkspacePath ./.wpa
pwsh ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.desktop.yaml -WorkspacePath ./.wpa
```

State that exit code 0 means a ready preview, 1 means no completed run due to fatal trust/publication failure, and 2 means a completed reviewable run with `blockedReasons`. Show the separate `show-run`, human `approve-run`, `invoke-run -WhatIf`, and `invoke-run` sequence. Explicitly state that preview never approves, applies, installs dependencies, changes PATH, adds sources, elevates, or remaps managers.

- [ ] **Step 4: Add a fixture-only `preview -WhatIf` CI smoke**

Append to the existing fixture-only smoke step in `.github/workflows/ci.yml`:

```powershell
$previewWorkspace = './TestResults/preview-whatif-workspace'
& ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.codex.yaml -WorkspacePath $previewWorkspace -WhatIf
if ($LASTEXITCODE -ne 0) { throw "preview WhatIf failed with exit code $LASTEXITCODE" }
if (Test-Path -LiteralPath $previewWorkspace) { throw 'preview WhatIf wrote workspace artifacts' }
```

This command must not probe or mutate a real manager because `New-WpaRun -WhatIf` returns before preparation.

- [ ] **Step 5: Run integration tests and the smoke command**

Run:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Integration/Cli.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$w='./TestResults/preview-whatif-local'; & ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.codex.yaml -WorkspacePath `$w -WhatIf; if(`$LASTEXITCODE -ne 0){exit `$LASTEXITCODE}; if(Test-Path -LiteralPath `$w){throw 'preview WhatIf wrote artifacts'}"
```

Expected: both commands PASS; the preview workspace does not exist.

- [ ] **Step 6: Commit Task 6 files only**

```powershell
git add README.md README.ja.md docs/usage.md docs/usage.ja.md docs/troubleshooting.md .github/workflows/ci.yml tests/Integration/Cli.Tests.ps1
git commit -m "docs: add safe preview workflow"
```

---

### Task 7: Run repository completion gates and submit for review

**Files:**
- Review only: all files changed in Tasks 1–6
- Preserve: `src/WinPkgAgent/Private/Adapters/Scoop.ps1`, `tests/Contract/Manager.Tests.ps1`

**Interfaces:**
- Consumes: all prior task deliverables.
- Produces: fresh verification evidence and a scoped diff ready for human review.

- [ ] **Step 1: Run schema and module import checks**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$ErrorActionPreference='Stop'; Get-ChildItem schemas -Filter '*.schema.json' -File | ForEach-Object { `$d=Get-Content `$_.FullName -Raw | ConvertFrom-Json; if(-not `$d.'`$schema' -or (-not `$d.type -and -not `$d.oneOf)){throw \"Invalid JSON Schema envelope: `$(`$_.Name)\"} }; Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1 -Force; Test-WpaManifest -Path ./config/packages.example.yaml | ConvertTo-Json -Depth 10"
```

Expected: exit 0 and manifest `valid: true`.

- [ ] **Step 2: Run all Pester suites with repository configuration**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: zero failed tests. Record the exact passed count.

- [ ] **Step 3: Run PSScriptAnalyzer when version 1.25.0 is available**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$ErrorActionPreference='Stop'; `$m=Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -EQ ([version]'1.25.0') | Select-Object -First 1; if(-not `$m){throw 'PSScriptAnalyzer 1.25.0 unavailable'}; Import-Module `$m.Path; `$f=@(Invoke-ScriptAnalyzer -Path ./src -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse; Invoke-ScriptAnalyzer -Path ./scripts -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse); if(`$f.Count){`$f|Format-Table -AutoSize; throw \"PSScriptAnalyzer found `$(`$f.Count) finding(s)\"}"
```

Expected: zero findings. If the pinned module is unavailable, report that exact gap and do not install it silently.

- [ ] **Step 4: Run fixture-only CLI WhatIf smoke**

Run Task 6 Step 5's smoke command again.

Expected: exit 0 and no workspace artifacts.

- [ ] **Step 5: Audit the final diff and secret/scope boundaries**

```powershell
git status --short
git diff --check
git diff --stat dd6fb75..HEAD
git diff --name-only dd6fb75..HEAD
git diff dd6fb75..HEAD -- scripts src tests README.md README.ja.md docs .github/workflows/ci.yml
```

Expected: only planned files are committed after `dd6fb75`; no approval bypass, force switch, secret, raw manager path persistence, uninstall, elevation, source-addition, or dependency-install path is present. The two pre-existing dirty files remain unstaged and are reported separately.

- [ ] **Step 6: Record Plane verification and move the item to Review**

Add one concise `WINPKGAG-2` comment listing the principal files, exact Pester count, schema/import result, PSScriptAnalyzer result or explicit availability gap, and fixture-only smoke result. Resolve the live REVIEW semantic; because this project currently has no named Review state, use the documented nearest started-state fallback and report that fallback. Do not move the item to Done.

- [ ] **Step 7: Request code review**

Use `superpowers:requesting-code-review` against the committed Task 1–6 diff. Address only findings within this specification; record unrelated findings without changing them.
