# Existing Package Migration Candidate Design

## Goal

Make as many currently installed packages manageable as possible without silently adopting ambiguous applications or changing real package state.

## Scope

- Use PowerShell 7.4 or newer for all implementation and verification commands.
- Treat WinGet and Scoop export records as detected packages, not proof that the manager originally installed them.
- Keep migration preparation read-only: inventory and candidate manifest generation may write only review artifacts.
- Fix empty manager exports so an empty Scoop installation is a valid successful inventory instead of a parse failure.
- Generate a reviewable candidate manifest with valid logical package names, explicit pending status, and warnings that source/category and migration ownership require human review.
- Preserve the existing approval gate and the prohibition on uninstall, elevation, source changes, reboot, driver, BIOS, firmware, and arbitrary command execution.

## Non-goals

- No automatic uninstall or replacement of an existing application.
- No fuzzy matching of arbitrary registry application names to package IDs.
- No package install, upgrade, or reinstallation before a human approves a generated plan.
- No attempt to make Scoop upgrades exact-version enforceable.

## Design

The existing manager adapters remain the source of package detection. WinGet export already attempts to match installed Windows applications to catalog IDs; Scoop export reports Scoop-owned applications. Each inventory package receives provenance metadata indicating the manager export that detected it. The candidate exporter converts IDs into deterministic manifest-safe logical names, preserves known source/version values, and leaves missing source/category values pending for human review.

An empty `apps` array in Scoop JSON and an empty package set in WinGet JSON produce an empty package list, not malformed inventory. Manager availability and version failures remain visible in the manager status and warnings.

## Approval boundary

The result is an inventory and pending candidate only. The human must review each candidate's manager ownership, source, category, and possible reinstall impact before creating an active manifest and approval digest. The implementation must never call an install or upgrade adapter during inventory or candidate generation.

## Verification

- Contract tests cover empty and non-empty WinGet/Scoop export parsing.
- Candidate tests cover safe logical names, pending review metadata, and preservation of source/version.
- PowerShell 7.6.3 direct smoke checks run the real read-only inventory and candidate generation with the user's manager context.
