# Publication directory identity design

**Date:** 2026-08-09
**Status:** Human-approved direction; written-spec review pending
**Scope:** Close the post-canonical directory/junction replacement blocker reported against `bf47e8b`, without changing public commands, schemas, approval behavior, or package-manager behavior.

## Problem

The dual-marker state machine keeps the sibling publication guard present until the in-run pending marker completes. However, the retained `OwnedDirectoryHandle` currently shares delete access. After the owned staging directory is renamed to the canonical run path, a competing process can therefore rename that directory and put a junction at the same canonical path. `New-WpaOwnedPublicationPendingMarker` then creates `.wpa-publication-pending` through the replaced absolute pathname and follows the junction outside the trusted workspace.

The sibling guard still blocks readers, so this is not the original mixed-marker TOCTOU. It is a separate destination-parent identity failure: exact ownership of the marker's source handle does not authenticate an absolute destination path whose directory can be replaced.

## Root-cause evidence

The final scoped review reproduced the failure with a temporary fixture: the canonical directory was displaced after its owned-handle rename, replaced by a junction, and the real pending-marker constructor created the marker in the junction target outside `workspace/runs`.

A separate ignored handle fixture compared the current and proposed sharing modes:

| Directory-handle sharing | Owner rename | Competing leaf rename | Competing `runs` rename | Competing workspace rename | Child creation | Pending-to-complete rename |
| --- | --- | --- | --- | --- | --- | --- |
| Read + Write + Delete (current) | succeeds | succeeds | not selected | not selected | succeeds | succeeds |
| Read + Write (selected) | succeeds | blocked | blocked | blocked | succeeds | succeeds |
| Read only | succeeds | blocked | not needed | not needed | succeeds | fails with sharing violation |

The selected mode is therefore Read + Write sharing without Delete sharing. Read-only sharing is too restrictive because the owned child marker cannot be renamed while the parent directory handle is open.

Microsoft documents that `NtCreateFile.ShareAccess` must be compatible with later requested access and that omitting `FILE_SHARE_DELETE` denies later delete-access opens. Rename requires an appropriately authorized handle and is performed through `SetFileInformationByHandle(FileRenameInfo)`:

- <https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntcreatefile>
- <https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileinformationbyhandle>
- <https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_rename_info>

## Considered approaches

### A. Deny competing directory delete/rename and verify retained identity — selected

Create the staging directory with the existing owner handle and `DELETE | FILE_READ_ATTRIBUTES` desired access, but share only Read and Write. The owner continues using `SetFileInformationByHandle` on that same handle to rename staging to canonical. No later opener can obtain the delete access needed to rename or remove the owned directory while publication is in progress.

Expose a read-only method on `OwnedDirectoryHandle` that obtains the current normalized path from the retained handle. Before every post-canonical marker transition, compare that handle-derived path with the expected canonical path and reject any reparse-point canonical item. Because competing delete/rename is denied for the handle lifetime, the comparison and following marker operation do not have the reproduced replacement window.

This is the smallest change that directly addresses the reproduced root cause and keeps the existing marker interfaces.

### B. Make every child operation relative to the directory handle — rejected for this fix

`NtCreateFile.RootDirectory` and `FILE_RENAME_INFO.RootDirectory` can bind child names to a directory handle. This would require extending both native wrappers, exposing or safely borrowing native handles, and changing all marker creation and completion calls. It is more invasive and still needs a stable canonical-to-owned-directory check before releasing the sibling guard, because handle-relative writes alone do not prevent readers from resolving a malicious replacement at the canonical path.

### C. Create and complete pending before the canonical rename — rejected

Creating pending under staging removes the pending-construction pathname window, but guard completion still targets the canonical path and must prove that path identifies the owned directory. It moves the defect rather than closing it.

## Architecture

### Owned directory handle

`OwnedDirectoryHandle.CreateAtomically` keeps its existing atomic `NtCreateFile(FILE_CREATE | FILE_DIRECTORY_FILE)` acquisition and desired access. Its share mask changes from:

```text
FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
```

to:

```text
FILE_SHARE_READ | FILE_SHARE_WRITE
```

The handle remains open continuously from staging creation through:

1. owned artifact writes and staged validation;
2. exact-handle rename to the canonical run path;
3. pending-marker creation;
4. final owned-content validation;
5. pending-marker completion;
6. sibling-guard completion.

Only the existing outer `finally` disposes it after publication has either completed or failed closed.

### Handle-derived path verification

Add `OwnedDirectoryHandle.GetFinalPath()` using `GetFinalPathNameByHandleW`. Normalize the returned DOS/extended path only in memory and compare it case-insensitively with `Path.GetFullPath(expectedCanonicalPath)`. Do not persist or include the raw path in errors or artifacts.

Add a private PowerShell assertion with this contract:

```text
Assert-WpaOwnedPublishedDirectoryTrust(Ownership, FinalPath) -> true or sanitized exception
```

It verifies:

- the directory handle is still open;
- its handle-derived final path equals the exact canonical path;
- the canonical item exists, is a directory, is not a reparse point, and is directly below the trusted `RunsPath`;
- the immutable sibling guard handle is open and its fixed sibling path still exists before publication.

Call it immediately after the exact directory rename, before pending creation, before pending completion, after pending completion, and immediately before guard completion. The final call occurs directly adjacent to the guard handle rename; no user code, callback, pathname creation, or validation loop runs between them.

### Failure behavior

Any sharing violation, handle/path mismatch, reparse detection, marker collision, or verification failure returns the existing sanitized `PREVIEW_STAGING_PRESERVED` boundary. The sibling guard remains at its fixed path unless the guard completion itself has already succeeded. No path-based deletion, overwrite, junction removal, retry bypass, or automatic ACL repair is added.

If post-canonical validation fails, evidence quarantine continues to move only the pending marker and owned directory by retained handles. The no-Delete-share directory handle does not block its own exact-handle evidence rename.

## Tests

Add deterministic Windows fixture tests before production changes.

1. **Share-mode characterization:** the real owner handle can rename staging to canonical, create/validate children, move pending to complete, and move the owned directory to evidence while open; competing leaf, `runs`, and workspace renames fail while the handle remains open.
2. **Pending-creation replacement regression:** immediately after the owned canonical rename, attempt to displace canonical and install a junction to an outside TestDrive sibling. Before the fix, the outside pending marker is created; after the fix, displacement is denied, no outside marker exists, the sibling guard remains, and the outward error is sanitized.
3. **Guard-release replacement regression:** during the pending-complete-to-guard-complete interval, attempt the same displacement/junction replacement. The displacement must be denied and `.wpa-publication-guard-complete` must remain inside the owned canonical directory.
4. **Identity mismatch/reparse fail-closed tests:** injected handle-path mismatch or canonical reparse state is rejected before any marker pathname operation and leaves the sibling guard.
5. **Regression suite:** existing evidence quarantine, completion failure, handle sharing, legacy no-marker, approval/invocation, fixture-only `-WhatIf`, and known full-suite baseline behavior remain unchanged.

Tests use only `TestDrive`, injected handles, or `-WhatIf`. They do not invoke WinGet, Scoop, package mutation, elevation, uninstall, source addition, PATH changes, or dependency installation.

## Acceptance criteria

- A competing process cannot rename/delete the owned canonical directory or its `runs`/workspace ancestry while the retained directory handle is open.
- Pending creation and both completion destinations are accepted only while the retained handle resolves to the exact canonical non-reparse directory.
- The reproduced junction attack creates no artifact outside the test workspace.
- The publisher's own canonical and evidence renames and child marker transitions continue to work.
- All publication failures leave the sibling guard or a non-exposed pre-canonical staging state and perform zero deletion.
- Focused affected tests pass; full Pester has only the three documented baseline failures; coverage remains at least 75 percent; schema/import/build and fixture-only `-WhatIf` pass.
- One fresh scoped review reports no Critical or Important finding in the new fix diff.

## Compatibility and exclusions

- No public PowerShell command, parameter, result schema, manifest schema, policy schema, or approval digest changes.
- No package operation is executed by this fix or its tests.
- No uninstall, elevation, reboot, driver, firmware, source-addition, dependency-installation, PATH-mutation, arbitrary-command, force, or approval-bypass path is added.
- Existing unrelated dirty Scoop adapter and manager-contract test files remain untouched and unstaged.
