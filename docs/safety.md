# Safety and threat model

v0.1 supports only `state: present`. There is no uninstall, elevation, reboot, source addition, driver, BIOS, firmware, or arbitrary command path. `-WhatIf` performs read-side validation but never calls a mutating adapter. Operations stop at the first failure.

| Threat | Control |
| --- | --- |
| Tampered or stale artifacts | Canonical content/full hashes, approval digest, expiry, inventory/policy/environment revalidation |
| Injection through manager arguments | Executable and argument arrays; allow-listed identifiers, sources, versions, command names, and paths |
| Path traversal/reparse redirection | Same-directory temporary writes, reparse-point rejection, atomic replacement |
| Secret leakage | Redaction of token-like values, profile paths, and credential assignments |
| Incomplete manager state | Partial/failed inventory blocks relevant mutation |
| AI or unattended approval | Interactive host and typed digest confirmation; no force switch or environment bypass |

The approval hash is not a signature. Keep plan and approval artifacts in an ACL-protected directory; a local actor able to replace both files can recompute their unkeyed hashes. Path checks reject traversal and observed reparse points, but do not claim protection against a same-user process racing directory replacement between validation and I/O.

Back up important data and review every plan before approval. This tool is not a rollback system.
