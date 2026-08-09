# Publication Directory Identity Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent post-canonical directory or ancestor replacement from redirecting publication markers outside the trusted workspace while preserving the existing fail-closed dual-marker workflow.

**Architecture:** Retain the atomic owned-directory handle from staging creation through sibling-guard completion, but deny delete sharing on that handle so competing directory and ancestor renames cannot open with delete access. Resolve the current path from the retained handle and assert that it still identifies the exact canonical, non-reparse run directory before every post-canonical marker transition; keep all public commands, artifacts, schemas, approval behavior, and package-manager behavior unchanged.

**Tech Stack:** PowerShell 7.4+, embedded C# Win32 interop (`NtCreateFile`, `SetFileInformationByHandle`, `GetFinalPathNameByHandleW`), Pester 5.6.1, JSON Schema.

## Global Constraints

- Preserve the inventory → plan → human typed-digest approval → apply → verify boundary; an AI agent never approves or bypasses approval.
- Do not invoke or add real package mutation, uninstall, elevation, source addition, dependency installation, PATH mutation, reboot, driver, firmware, arbitrary-command, force, or approval-bypass behavior.
- Keep publication artifacts and failure evidence inside the trusted workspace `runs` directory; never delete, overwrite, repair, or follow an unknown/reparse replacement.
- Use absolute `C:\Program Files\PowerShell\7\pwsh.exe` for every repository PowerShell command and never fall back to `powershell.exe`.
- Tests use only `TestDrive`, injected objects, or `-WhatIf`; they never invoke WinGet, Scoop, or another real package manager.
- Preserve and never stage the unrelated dirty files `src/WinPkgAgent/Private/Adapters/Scoop.ps1` and `tests/Contract/Manager.Tests.ps1`.
- Do not change a public PowerShell command, parameter, module export, result schema, manifest schema, policy schema, approval digest, or legacy no-marker read behavior.
- Keep the sibling publication guard open and present until pending completion and final directory-identity verification have both succeeded.
- Convert trust/identity failures at this boundary to the fixed outward error `PREVIEW_STAGING_PRESERVED`; never persist or log raw host paths returned from a native handle.
- PSScriptAnalyzer 1.25.0 may be run only if already installed; do not install it or any other dependency.

## File structure

- `src/WinPkgAgent/Private/Workspace/RunPublication.ps1`: change only the owned-directory handle sharing/path API, add the private post-canonical trust assertion, and wire it into publication transitions.
- `tests/Unit/Workspace.Tests.ps1`: add Windows fixture regressions for directory/ancestor sharing, canonical-junction replacement, guard release, and injected identity failures.
- `docs/superpowers/specs/2026-08-09-publication-directory-identity-design.md`: approved source of requirements; no implementation detail should expand beyond it.

The native handle and the PowerShell state machine change together and cannot be independently accepted safely. Keep all source and test work below in one implementation task and one implementation commit.

---

### Task 1: Bind publication transitions to the retained canonical directory

**Files:**
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1:1-224`
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1:661-699`
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1:699-881`
- Modify: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1:902-992`
- Test: `tests/Unit/Workspace.Tests.ps1:446-1160`

**Interfaces:**
- Consumes: `[WinPkgAgent.Native.OwnedDirectoryHandle]::CreateAtomically(string path)`, its retained `IsOpen`, `Rename(string destinationPath)`, and `Dispose()` members, and the existing immutable `PublicationGuard`/`PublicationPendingMarker` ownership properties.
- Produces: `[WinPkgAgent.Native.OwnedDirectoryHandle].GetFinalPath() -> string` returning an in-memory normalized full DOS/UNC path, and private `Assert-WpaOwnedPublishedDirectoryTrust -Ownership <object> -FinalPath <string> -> $true` or the sanitized `PREVIEW_STAGING_PRESERVED` exception.
- Preserves: `New-WpaOwnedPublicationPendingMarker`, `Assert-WpaOwnedStagingContents`, `Complete-WpaOwnedRunPublication`, `Move-WpaOwnedRunToStagingEvidence`, and `Publish-WpaPreparedRun` signatures.

- [ ] **Step 1: Add the real-handle sharing regression and verify RED**

Add an `It 'keeps directory and ancestor renames blocked while the owned handle is open'` fixture beside the existing atomic-acquisition tests. Use one `TestDrive` tree, create the staging directory only through `New-WpaOwnedDirectoryHandleAtomically`, and exercise the owner handle and competing path opens explicitly:

```powershell
$workspace = Join-Path $TestDrive 'directory-share-mode/workspace'
$runs = Join-Path $workspace 'runs'
$staging = Join-Path $runs '.staging-20260809-010203-aabbccdd'
$final = Join-Path $runs '20260809-010203-aabbccdd'
$evidence = Join-Path $runs '.staging-evidence-20260809-010203-aabbccdd-deadbeef'
$afterClose = Join-Path $runs '.staging-after-close'
[IO.Directory]::CreateDirectory($runs) | Out-Null
$handle = New-WpaOwnedDirectoryHandleAtomically -Path $staging
$marker = $null
try {
    $handle.Rename($final)
    [IO.File]::WriteAllText((Join-Path $final 'child.txt'), 'owned')
    $marker = [WinPkgAgent.Native.OwnedPublicationMarker]::CreateAtomically(
        (Join-Path $final '.wpa-publication-pending'), 'token')
    $marker.Rename((Join-Path $final '.wpa-publication-complete'))

    { [IO.Directory]::Move($final, (Join-Path $runs 'displaced-leaf')) } | Should -Throw
    { [IO.Directory]::Move($runs, (Join-Path $workspace 'displaced-runs')) } | Should -Throw
    { [IO.Directory]::Move($workspace, (Join-Path $TestDrive 'displaced-workspace')) } | Should -Throw

    $handle.Rename($evidence)
    Test-Path (Join-Path $evidence 'child.txt') | Should -BeTrue
    Test-Path (Join-Path $evidence '.wpa-publication-complete') | Should -BeTrue
} finally {
    if ($null -ne $marker) { $marker.Dispose() }
    if ($null -ne $handle) { $handle.Dispose() }
}
[IO.Directory]::Move($evidence, $afterClose)
Test-Path $afterClose | Should -BeTrue
```

Run only the workspace suite:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Workspace.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected RED on `bf47e8b`/`7e268c1`: at least the competing leaf rename succeeds because the owned directory was opened with `FILE_SHARE_DELETE`.

- [ ] **Step 2: Add the pending-creation junction regression while still RED**

Add `It 'blocks canonical displacement before pending marker creation'`. Keep the outside target inside `TestDrive` but outside the test workspace. Construct real staging ownership and a real sibling guard, rename the owner handle to canonical, attempt the exact displacement/junction attack, then create pending through the production helper:

```powershell
$outside = Join-Path $TestDrive 'pending-attack-outside'
$displaced = Join-Path $runs '.displaced-owned-run'
[IO.Directory]::CreateDirectory($outside) | Out-Null
$attackSucceeded = $false
try {
    [IO.Directory]::Move($final, $displaced)
    New-Item -ItemType Junction -Path $final -Target $outside -ErrorAction Stop | Out-Null
    $attackSucceeded = $true
} catch {
    $attackSucceeded = $false
}
New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $final | Out-Null

$attackSucceeded | Should -BeFalse
Test-Path (Join-Path $outside '.wpa-publication-pending') | Should -BeFalse
Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeTrue
Test-Path $ownership.PublicationGuardPath | Should -BeTrue
```

Create `$ownership` with `New-WpaRunStagingOwnership`, call `New-WpaOwnedPublicationGuard`, release only the delete-on-close staging-owner stream, and keep all three retained handles open until `finally { Close-WpaRunStagingOwnershipHandles -Ownership $ownership }`. Do not add cleanup or deletion calls; Pester owns the entire `TestDrive` fixture.

Run the Step 1 command again. Expected RED before production changes: `$attackSucceeded` is true and the pending marker is created through the junction under `$outside`.

- [ ] **Step 3: Add the guard-release junction regression while still RED**

Add `It 'blocks canonical displacement immediately before guard release'`. Use a real owned directory and real pending marker. Close the real guard handle after creation, replace only the in-memory guard object with a fake that keeps the real sibling guard file in place, and have its `Rename` method attempt displacement immediately before moving that guard file:

```powershell
$guard = [pscustomobject]@{
    IsOpen = $true
    DisplacementSucceeded = $false
    DisplacementBlocked = $false
    SourcePath = $ownership.PublicationGuardPath
}
$guard | Add-Member ScriptMethod Rename {
    param($DestinationPath)
    try {
        [IO.Directory]::Move($final, $displaced)
        New-Item -ItemType Junction -Path $final -Target $outside -ErrorAction Stop | Out-Null
        $this.DisplacementSucceeded = $true
    } catch {
        $this.DisplacementBlocked = $true
    }
    [IO.File]::Move($this.SourcePath, $DestinationPath)
    $this.SourcePath = $DestinationPath
}
$guard | Add-Member ScriptMethod Dispose { $this.IsOpen = $false }
$ownership.PublicationGuard = $guard

Complete-WpaOwnedRunPublication -Ownership $ownership -FinalPath $final

$guard.DisplacementSucceeded | Should -BeFalse
$guard.DisplacementBlocked | Should -BeTrue
Test-Path (Join-Path $outside '.wpa-publication-guard-complete') | Should -BeFalse
Test-Path (Join-Path $final '.wpa-publication-guard-complete') | Should -BeTrue
```

Before assigning the fake, call `$ownership.PublicationGuard.Dispose()` without deleting the guard file. Keep the real directory and pending handles open through completion. Expected RED: the current delete-sharing mode permits displacement and moves `.wpa-publication-guard-complete` through the junction to `$outside`.

- [ ] **Step 4: Add handle-path mismatch and reparse tests while still RED**

Add these two tests and assert both the fixed error and absence of an outside/new pending marker:

```powershell
It 'rejects a handle-derived final-path mismatch before pending creation' {
    $directory = [pscustomobject]@{ IsOpen = $true; FinalPath = (Join-Path $runs 'different-run') }
    $directory | Add-Member ScriptMethod GetFinalPath { $this.FinalPath }
    $ownership.DirectoryHandle = $directory

    $message = try {
        New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $final
        ''
    } catch { $_.Exception.Message }

    $message | Should -BeExactly 'PREVIEW_STAGING_PRESERVED'
    $message | Should -Not -Match ([regex]::Escape($TestDrive))
    Test-Path (Join-Path $final '.wpa-publication-pending') | Should -BeFalse
}

It 'rejects a canonical reparse point before pending creation' {
    New-Item -ItemType Junction -Path $final -Target $outside -ErrorAction Stop | Out-Null
    $directory = [pscustomobject]@{ IsOpen = $true; FinalPath = [IO.Path]::GetFullPath($final) }
    $directory | Add-Member ScriptMethod GetFinalPath { $this.FinalPath }
    $ownership.DirectoryHandle = $directory

    { New-WpaOwnedPublicationPendingMarker -Ownership $ownership -FinalPath $final } |
        Should -Throw 'PREVIEW_STAGING_PRESERVED'
    Test-Path (Join-Path $outside '.wpa-publication-pending') | Should -BeFalse
    Test-Path $ownership.PublicationGuardPath | Should -BeTrue
}
```

For each test, create an actual workspace/runs/final or junction and sibling guard file, plus fake open guard and directory objects containing only the members consumed by the trust assertion. The expected RED is a missing trust helper/`GetFinalPath` contract or creation through the reparse path. No production code is changed until Steps 1-4 have demonstrated the failures.

- [ ] **Step 5: Remove delete sharing from only the owned directory handle**

In `OwnedDirectoryHandle`, remove `FileShareDelete` if it becomes unused and change only the `NtCreateFile` directory `shareAccess` argument:

```csharp
FileShareRead | FileShareWrite,
```

Do not alter `DeleteAccess | ReadAttributesAccess`, `FileCreate`, `FileDirectoryFile`, or `OwnedPublicationMarker` sharing. The existing handle must retain delete access so its own `SetFileInformationByHandle(FileRenameInfo)` canonical/evidence renames continue to work.

- [ ] **Step 6: Add robust handle-derived final-path resolution**

Add `using System.Text;` to the `OwnedDirectoryHandle` type definition and this public method plus private normalization helper. Buffer growth must follow the API return value, stay bounded, and avoid exposing the raw native path:

```csharp
public string GetFinalPath()
{
    if (!IsOpen)
    {
        throw new InvalidOperationException("Directory ownership handle is closed.");
    }

    uint capacity = 260;
    for (int attempt = 0; attempt < 3; attempt++)
    {
        StringBuilder buffer = new StringBuilder(checked((int)capacity));
        uint length = GetFinalPathNameByHandle(handle, buffer, capacity, 0);
        if (length == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        if (length < capacity)
        {
            return NormalizeFinalPath(buffer.ToString());
        }
        if (length > 32768)
        {
            throw new IOException("Owned directory path is too long.");
        }
        capacity = checked(length + 1);
    }
    throw new IOException("Owned directory path could not be resolved.");
}

private static string NormalizeFinalPath(string path)
{
    if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
    {
        return Path.GetFullPath(@"\\" + path.Substring(8));
    }
    if (path.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
    {
        return Path.GetFullPath(path.Substring(4));
    }
    return Path.GetFullPath(path);
}
```

Add the matching P/Invoke to `OwnedDirectoryHandle` only:

```csharp
[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true,
    EntryPoint = "GetFinalPathNameByHandleW")]
private static extern uint GetFinalPathNameByHandle(
    SafeFileHandle fileHandle,
    StringBuilder filePath,
    uint filePathLength,
    uint flags);
```

The normalized string is an internal comparison value only. Never add it to an exception, object returned by a public command, run artifact, log, or Plane comment.

- [ ] **Step 7: Add the post-canonical trust assertion**

Place the new private function immediately before `New-WpaOwnedPublicationPendingMarker` and implement the complete fail-closed contract:

```powershell
function Assert-WpaOwnedPublishedDirectoryTrust {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Ownership,
        [Parameter(Mandatory)][string]$FinalPath
    )

    try {
        if ($null -eq $Ownership.DirectoryHandle -or -not $Ownership.DirectoryHandle.IsOpen) {
            throw 'directory handle unavailable'
        }
        $workspaceFull = [IO.Path]::GetFullPath([string]$Ownership.WorkspacePath)
        $runsFull = [IO.Path]::GetFullPath([string]$Ownership.RunsPath)
        $finalFull = [IO.Path]::GetFullPath($FinalPath)
        $handleFull = [IO.Path]::GetFullPath([string]$Ownership.DirectoryHandle.GetFinalPath())
        if (-not [string]::Equals([IO.Path]::GetDirectoryName($runsFull), $workspaceFull, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals([IO.Path]::GetDirectoryName($finalFull), $runsFull, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals($handleFull, $finalFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'published directory identity mismatch'
        }

        Assert-WpaTrustedPublicationAncestry -WorkspacePath $workspaceFull -RunsPath $runsFull -StagingPath $finalFull -StagingMustExist | Out-Null
        $finalItem = Get-Item -LiteralPath $finalFull -Force -ErrorAction Stop
        if (-not $finalItem.PSIsContainer -or
            ($finalItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::Equals($finalItem.Parent.FullName, $runsFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'published directory is not trusted'
        }

        $expectedGuardPath = [IO.Path]::GetFullPath((Join-Path $runsFull ".wpa-publication-guard-$([IO.Path]::GetFileName($finalFull))"))
        $guardFull = [IO.Path]::GetFullPath([string]$Ownership.PublicationGuardPath)
        if ($null -eq $Ownership.PublicationGuard -or -not $Ownership.PublicationGuard.IsOpen -or
            -not [string]::Equals($guardFull, $expectedGuardPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'publication guard identity mismatch'
        }
        $guardItem = Get-Item -LiteralPath $guardFull -Force -ErrorAction Stop
        if ($guardItem.PSIsContainer -or
            ($guardItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not [string]::Equals($guardItem.Directory.FullName, $runsFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'publication guard is not trusted'
        }
    } catch {
        throw 'PREVIEW_STAGING_PRESERVED'
    }
    return $true
}
```

Keep every diagnostic inside the `try`; the only outward exception is the fixed sanitized value. Do not weaken `Assert-WpaTrustedPublicationAncestry` or add retries, repair, deletion, or path-following fallback.

- [ ] **Step 8: Wire the assertion at every approved lifecycle boundary**

Make these exact state-machine changes:

1. In `Publish-WpaPreparedRun`, immediately after `Move-WpaOwnedRunStagingDirectory`, call the assertion before invoking the pending constructor.
2. At the start of `New-WpaOwnedPublicationPendingMarker`, call the assertion before calculating, probing, or creating the pending pathname.
3. In the `OwnershipReleased` branch of `Assert-WpaOwnedStagingContents`, replace its weaker directory-only check with the assertion before enumerating children.
4. In `Complete-WpaOwnedRunPublication`, call the assertion before destination-path probes and again directly before `PublicationPendingMarker.Rename`.
5. After pending rename and its existing presence verification, call the assertion once more, then invoke `PublicationGuard.Rename` on the immediately following executable line. Do not place a callback, path creation, content loop, or other validation between this final assertion and guard rename.

The intended completion core is:

```powershell
Assert-WpaOwnedPublishedDirectoryTrust -Ownership $Ownership -FinalPath $finalFull | Out-Null
$Ownership.PublicationPendingMarker.Rename($pendingCompletePath)
$Ownership.PublicationPendingPath = $pendingCompletePath
if ((Test-Path -LiteralPath $originalPendingPath -ErrorAction Stop) -or
    -not (Test-Path -LiteralPath $pendingCompletePath -ErrorAction Stop) -or
    -not (Test-Path -LiteralPath $Ownership.PublicationGuardPath -ErrorAction Stop)) {
    throw 'Publication marker completion could not be verified.'
}
Assert-WpaOwnedPublishedDirectoryTrust -Ownership $Ownership -FinalPath $finalFull | Out-Null
$Ownership.PublicationGuard.Rename($guardCompletePath)
```

Do not dispose `DirectoryHandle` until the existing outer `finally`. Do not change evidence quarantine: its exact retained handle must still rename the owned directory while the fixed sibling guard remains present.

- [ ] **Step 9: Run the closest suite and verify GREEN**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests/Unit/Workspace.Tests.ps1' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: every workspace test passes. Confirm specifically that all five new tests pass, no marker exists in either outside fixture, owner canonical/evidence renames still work, ancestor renames are blocked only while the handle is open, and failure messages contain no `TestDrive` path.

- [ ] **Step 10: Run the affected safety suites**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path @('./tests/Unit/Workspace.Tests.ps1','./tests/Unit/Planning.Tests.ps1','./tests/Unit/ApprovalExecution.Tests.ps1') -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: all affected tests pass (the previous baseline was 98/98, so this run must discover and pass at least 103 tests after the five additions). Existing legacy no-marker reads, pending readers, approval/invocation rejection, evidence quarantine, collision, and completion-failure tests remain green.

- [ ] **Step 11: Inspect and commit only the atomic implementation**

```powershell
git diff --check -- src/WinPkgAgent/Private/Workspace/RunPublication.ps1 tests/Unit/Workspace.Tests.ps1
git diff -- src/WinPkgAgent/Private/Workspace/RunPublication.ps1 tests/Unit/Workspace.Tests.ps1
git add src/WinPkgAgent/Private/Workspace/RunPublication.ps1 tests/Unit/Workspace.Tests.ps1
git diff --cached --name-only
git commit -m "fix: bind publication to owned directory"
```

The cached name list must contain exactly the two implementation files. Abort the commit if either unrelated Scoop/manager-contract file is staged.

---

### Task 2: Verify and review the bounded security fix

**Files:**
- Review: `src/WinPkgAgent/Private/Workspace/RunPublication.ps1`
- Review: `tests/Unit/Workspace.Tests.ps1`
- Reference: `docs/superpowers/specs/2026-08-09-publication-directory-identity-design.md`
- Preserve unstaged: `src/WinPkgAgent/Private/Adapters/Scoop.ps1`
- Preserve unstaged: `tests/Contract/Manager.Tests.ps1`

**Interfaces:**
- Consumes: the Task 1 implementation commit based on `7e268c1`.
- Produces: fresh parser/build/schema/Pester/fixture evidence, exactly one fresh scoped Sol security review, and a concise Plane `WINPKGAG-2` review submission using the existing In Progress fallback.

- [ ] **Step 1: Parse both changed PowerShell files**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$ErrorActionPreference='Stop'; foreach(`$p in @('./src/WinPkgAgent/Private/Workspace/RunPublication.ps1','./tests/Unit/Workspace.Tests.ps1')){`$tokens=`$null;`$errors=`$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path `$p),[ref]`$tokens,[ref]`$errors)|Out-Null;if(`$errors.Count){`$errors|Format-List;throw \"Parser errors in `$p\"}}"
```

Expected: exit 0 with zero parser errors.

- [ ] **Step 2: Run schema, module import, example manifest, and build checks**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$ErrorActionPreference='Stop'; Get-ChildItem schemas -Filter '*.schema.json' -File | ForEach-Object { `$d=Get-Content `$_.FullName -Raw | ConvertFrom-Json; if(-not `$d.'`$schema' -or (-not `$d.type -and -not `$d.oneOf)){throw \"Invalid JSON Schema envelope: `$(`$_.Name)\"} }; Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1 -Force; Test-WpaManifest -Path ./config/packages.example.yaml | Out-Null"
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File ./scripts/build.ps1 -SkipTests
```

Expected: both commands exit 0. These checks do not install dependencies or invoke package managers.

- [ ] **Step 3: Run full Pester with repository coverage configuration**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command ". ./tests/PesterConfiguration.ps1; `$c=Get-WpaPesterConfiguration -Path './tests' -DisableRegistry; Invoke-Pester -Configuration `$c"
```

Expected: no new failure; only these three documented baseline failures may remain:

- empty Winget export count;
- empty Scoop export count;
- package migration candidate `profiles: []` formatting.

Record the fresh discovered/passed/failed counts and line coverage. Coverage must remain at least 75 percent (previous evidence: 261 discovered, 258 passed, 3 known failed, 75.47 percent before these new tests).

- [ ] **Step 4: Check PSScriptAnalyzer without installing it**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$m=Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -EQ ([version]'1.25.0') | Select-Object -First 1; if(-not `$m){'PSScriptAnalyzer 1.25.0 unavailable'; exit 0}; Import-Module `$m.Path; `$f=@(Invoke-ScriptAnalyzer -Path ./src -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse; Invoke-ScriptAnalyzer -Path ./scripts -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse); if(`$f.Count){`$f|Format-Table -AutoSize; throw \"PSScriptAnalyzer found `$(`$f.Count) finding(s)\"}"
```

Expected in the current environment: report `PSScriptAnalyzer 1.25.0 unavailable` and continue. Do not call `Install-Module`, Scoop, WinGet, or another installer.

- [ ] **Step 5: Run the fixture-only preview `-WhatIf` smoke**

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -Command "`$w=Join-Path ([IO.Path]::GetFullPath('./TestResults')) ('publication-identity-preview-whatif-'+[guid]::NewGuid().ToString('N')); & ./scripts/winpkg-agent.ps1 preview -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.codex.yaml -WorkspacePath `$w -WhatIf; if(`$LASTEXITCODE -ne 0){exit `$LASTEXITCODE}; if(Test-Path -LiteralPath `$w){throw 'preview WhatIf wrote artifacts'}"
```

Expected: exit 0 and no workspace artifacts. This path returns before inventory/manager probes and performs no real package operation.

- [ ] **Step 6: Audit scope, no-delete behavior, and raw-path leakage**

```powershell
git diff --check 7e268c1..HEAD
git diff --name-only 7e268c1..HEAD
git status --short
rg -n "FileShareDelete|GetFinalPath|Assert-WpaOwnedPublishedDirectoryTrust|PREVIEW_STAGING_PRESERVED|Remove-Item|uninstall|elevat|source add|approval.*bypass" src/WinPkgAgent/Private/Workspace/RunPublication.ps1 tests/Unit/Workspace.Tests.ps1
```

Expected: the implementation commit changes only the source and workspace test; `OwnedPublicationMarker` sharing is unchanged; no production deletion/repair/bypass path or raw handle-derived path output was added; the two unrelated dirty files remain modified but unstaged.

- [ ] **Step 7: Request exactly one fresh scoped Sol review**

Use `superpowers:requesting-code-review`. Review only the new implementation range `7e268c1..HEAD` against `docs/superpowers/specs/2026-08-09-publication-directory-identity-design.md`, while treating the two unrelated unstaged files as out of scope. Require:

- findings ranked Critical, Important, or Minor with exact file/line evidence;
- explicit analysis of delete-sharing semantics for leaf, `runs`, and workspace ancestors;
- explicit analysis of the `GetFinalPathNameByHandleW` buffer/normalization contract;
- explicit analysis of every assertion placement, the pending-completion/guard-release adjacency, evidence quarantine, and sanitized failure behavior;
- confirmation that tests cannot write outside `TestDrive` or invoke a real package manager;
- final `PASS` only when no Critical or Important finding remains.

This is the one fresh Sol review authorized for this fix. If it returns Critical or Important, do not implement another fix wave; stop, preserve evidence, and request new human approval.

- [ ] **Step 8: Submit Plane work item `WINPKGAG-2` for human review**

After local verification and Sol PASS, post one concise Plane comment with these exact sections and facts:

- `## Implementation`: state that post-canonical publication is bound to the retained non-delete-shared directory handle and exact handle-derived canonical path, and that fixture regressions cover directory/ancestor displacement, junction redirection, and identity mismatch.
- `## Verification`: copy the exact workspace/affected/full Pester discovered, passed, and failed counts from the fresh runs; name only the three documented baseline failures; copy the fresh coverage percentage; report parser, schema/import/example-manifest, build, fixture-only preview `-WhatIf`, PSScriptAnalyzer availability/result, and the scoped Sol PASS.
- `## Notes`: state that no real package operation ran and that the unrelated Scoop/manager-contract edits remain unstaged.

Resolve REVIEW from live project states. This project has no named Review state, so retain the nearest started-state fallback (`In Progress`) and report that fallback. Do not move `WINPKGAG-2` to Done unless the user explicitly instructs it.

## Completion gate

Stop when Task 1 is committed, all Task 2 checks have fresh evidence, the one authorized Sol review reports no Critical/Important finding, Plane is synchronized to the documented review fallback, and the unrelated dirty files remain untouched. Do not run a real Scoop/WinGet command or apply any package plan as part of this implementation.
