# Changelog

All notable changes will be documented here. Until the first tagged release, entries describe repository intent and verified behavior only.

## Unreleased

- Establishes the fail-closed inventory → plan → approval → apply → verify contract.
- Documents v0.1 boundaries: `state: present` only; no uninstall, elevation, reboot, driver, firmware, or arbitrary command execution.
- Adds official-action-only Windows CI design and explicit development dependency installation.
- Adds path-safe run workspaces, explicit post-reboot verification, conservative ACL trust assessment, journal operation identity, project initialization, and pending manifest candidates.
