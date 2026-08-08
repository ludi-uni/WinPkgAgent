# Read-only unmanaged package observations design

## Goal

Detect installed Windows applications that are visible to `winget list` but are not present in the current WinGet export, while keeping ambiguous entries outside the active manifest and approval path.

## Scope

- Run WinGet `list --disable-interactivity` through the existing absolute-executable process adapter.
- Parse only the known English and Japanese table headers and fixed column boundaries.
- Compare observed IDs with the supplied inventory's package IDs.
- Write a separate JSON review artifact containing only observations not present in the export inventory.
- Classify observations with a stable ID/source as `manager-candidate`; classify ARP/MSIX or source-less entries as `manual-mapping`.
- Keep every observation `reviewStatus: pending`.

## Non-goals

- Do not fuzzy-match display names to WinGet IDs.
- Do not treat ARP/MSIX identifiers as installable package IDs.
- Do not modify the existing inventory schema or active manifest schema.
- Do not install, upgrade, uninstall, elevate, reboot, add sources, or approve plans.
- Do not persist executable paths or raw command diagnostics.

## Design

`ConvertFrom-WpaWingetList` is a strict pure parser. It locates a recognized English or Japanese header, derives the ID/version/available/source column offsets from that header, skips only the separator line, and rejects malformed non-empty rows. A successful header with no rows returns an empty array; an unknown header or malformed row returns `$null`.

`Get-WpaWingetUnmanagedObservations` resolves the verified WinGet executable and invokes only `list --disable-interactivity`. It parses the result, excludes IDs already present in the supplied inventory, and returns structured observations with `detectedBy = winget-list`. A row is `manager-candidate` only when its ID matches the documented manager-ID allow-list and its source is non-empty. Other rows are `manual-mapping` and cannot enter an active manifest without human mapping.

The process adapter keeps its normal redacted/truncated diagnostic behavior. The list call opts into redacted but non-truncated in-memory stdout only because a long ARP/MSIX ID can exceed WinGet's display column width; the full output is parsed immediately and is not persisted.

`Export-WpaUnmanagedCandidate` reads an existing inventory artifact, calls the read-only observation adapter, and writes `unmanaged-candidate.schema.json` data with `reviewStatus = pending`. This artifact is deliberately separate from `migration-candidate.yaml`, so no downstream plan can consume it accidentally as an active manifest.

## Safety and failure handling

- No source agreements or package mutation switches are passed to WinGet.
- Parser uncertainty produces `partial` or `failed` status and no guessed observations.
- Empty output with a recognized header is a valid empty observation set.
- The output contains display names, IDs, versions, source values, stable reason codes, and review state only; no paths, usernames, or raw stderr.
- The existing `Approve-WpaPlan` typed-digest gate remains unchanged.

## Verification

- Contract tests cover English/Japanese headers, empty output, source-less ARP/MSIX rows, malformed rows, and the absence of source-agreement arguments.
- Unit tests cover exclusion of export IDs, actionability classification, pending output, and schema validation.
- PowerShell 7.6.3 live smoke checks compare the new observation count with the current inventory without invoking mutation adapters.
