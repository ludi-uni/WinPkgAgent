# Dual publication marker design

**Date:** 2026-08-09  
**Status:** Human-approved design, written-spec review pending  
**Scope:** Close the remaining preview publication TOCTOU in `349655d` without changing package-management or approval behavior.

## Problem

Commit `349655d` uses one owned marker that moves between a sibling guard name and the canonical run's `.wpa-publication-pending` name. During evidence quarantine it moves pending back to guard. `Read-WpaRun` checks guard once and then pending once, so a concurrent reader can observe guard before the move and pending after the move, see neither, and consume failed content at the canonical run path.

The defect is architectural: no ordering of two independent path checks can prove a stable unpublished state while one marker is allowed to move repeatedly between those paths.

## Considered approaches

### A. Immutable guard plus separate in-run marker — selected

Create two independently owned marker objects. The sibling guard is created before publication and never changes name while the run is unpublished. After the exact staging directory reaches the canonical path, create a separate in-run pending marker. Validate final contents while both are present. Complete the in-run marker first, then release the sibling guard by exact handle rename as the final publication point.

This removes the mixed-state observation: every unpublished state has the same sibling guard path. It also lets evidence quarantine move the in-run marker out of the directory while the immutable guard continues blocking readers.

### B. Recheck guard and pending repeatedly — rejected

Additional guard/pending checks can close one transition ordering, but a pending-to-guard-to-pending sequence can still occur between checks. A retry loop also needs a reliable stable-state proof or timeout policy, neither of which exists in the current filesystem contract.

### C. Require readers to acquire a new cross-process lock — rejected

A named mutex or lock-file protocol could serialize publication and consumption, but it would change every show, approval, invocation, and recovery entry point. It is more invasive, introduces abandoned-lock behavior, and is unnecessary when an immutable guard can represent the unpublished state.

## Architecture

The publisher owns two handles:

1. **Publication guard**
   - Path: `runs/.wpa-publication-guard-<runId>`.
   - Created atomically before the staging directory is exposed.
   - Opened with delete access for its owning handle and read-only sharing, preventing competing write, delete, or replacement opens.
   - Its path remains unchanged throughout preparation, canonical rename, final validation, and any evidence-quarantine attempt.

2. **Run pending marker**
   - Path while unpublished: `<final>/.wpa-publication-pending`.
   - A distinct file and handle, created atomically only after the exact owned staging directory reaches `<final>` while the immutable guard still blocks all consumers.
   - Included in final owned-content validation through its retained handle.
   - Renamed by its exact handle to `<final>/.wpa-publication-complete` after final validation succeeds.

`Read-WpaRun` checks the immutable sibling guard before metadata and also rejects the in-run pending marker. Approval, invocation, show, and stage transitions continue entering through `Read-WpaRun`.

## State flow

### Successful publication

1. Atomically create and retain the sibling guard.
2. Build and validate the owned staging directory.
3. Rename the exact owned staging-directory handle to the canonical final path.
4. Atomically create and retain the distinct in-run pending marker.
5. Validate the complete final owned content, including the pending marker.
6. Rename the exact pending-marker handle to `.wpa-publication-complete`.
7. Revalidate marker path invariants.
8. Rename the exact immutable-guard handle to `<final>/.wpa-publication-guard-complete`.
9. Revalidate that the sibling guard and in-run pending paths are absent and both completed markers exist.

Step 8 is the publication point. Before it, the sibling guard always blocks readers. After it, the final content and both exact markers have completed.

### Failure before canonical directory rename

The staging directory is preserved. The guard remains at its fixed sibling path until its exact handle can be moved into the staging evidence directory. If that marker move fails, the sibling guard remains. No path-based deletion occurs.

### Final-content validation failure

The sibling guard stays fixed. Rename the exact in-run pending-marker handle to an evidence-safe sibling name, then rename the exact owned directory handle to a collision-safe staging-evidence directory. After a successful directory move, rename the pending marker into that evidence directory. If any rename fails or exhausts retries, at least the immutable guard remains at its original sibling path and the operation returns `PREVIEW_STAGING_PRESERVED`.

### Completion failure

If the in-run pending-to-complete rename fails, both the sibling guard and in-run pending marker remain. If guard completion fails after the in-run marker completes, the unchanged sibling guard remains and readers still reject the run. No marker or evidence is deleted.

## Compatibility and safety

- Legacy runs with neither guard nor pending marker remain readable.
- Completed runs may contain `.wpa-publication-complete` and `.wpa-publication-guard-complete`; neither changes public run metadata or schemas.
- No public command signature changes.
- No approval bypass, package mutation, uninstall, elevation, source addition, dependency installation, PATH mutation, driver, firmware, or reboot path is added.
- Failure artifacts remain within the workspace's `runs` directory.
- Unknown or replacement paths are never deleted or overwritten.

## Test design

Add deterministic tests before production changes:

1. A transition hook pauses after the in-run pending marker moves toward evidence while the immutable sibling guard remains. `Read-WpaRun`, `Approve-WpaRun`, and `Invoke-WpaRun` must all reject before metadata or plan operations.
2. Evidence rename collision/exhaustion must leave the immutable guard at its original path and perform zero deletion.
3. In-run completion failure must leave guard plus pending; guard completion failure must leave the sibling guard even if the in-run marker completed.
4. Successful publication must leave no sibling guard or in-run pending marker and must contain both completed markers.
5. Guard and pending handles must reject competing write/delete/replacement attempts.
6. Existing manager-scope, fingerprint binding, legacy-run compatibility, fixture-only `-WhatIf`, and three known baseline failures remain unchanged.

## Acceptance criteria

- No interleaving during publication or evidence quarantine can make both blocking paths absent before final publication.
- All show, approval, invocation, and stage consumers fail closed while either blocking path exists.
- Evidence quarantine and marker failures perform no deletion and return the fixed sanitized error.
- Focused affected tests pass, full Pester has only the three documented baseline failures, coverage remains at least 75 percent, schema/import validation passes, and fixture-only `-WhatIf` writes nothing.
- A fresh scoped security review reports all residual blockers closed and no new Critical or Important finding in the new diff.
