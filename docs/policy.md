# Policy and manifest guidance

Policy is an explicit input to planning. Keep package identifiers, sources, allowed versions, verification commands, and output paths allow-listed. A blocked, unknown, unmanaged, stale, partial, or ambiguous input must remain visible with a stable reason code and cannot be approved by a shortcut.

The v0.1 manifest accepts `state: present` only. Do not add an uninstall state or an unrestricted command field. Review maximum operation limits and protected-package rules before approval.
