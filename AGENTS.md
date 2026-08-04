# Contribution and agent rules

- Follow the five stages exactly: inventory, plan, approval, apply, verify.
- Acquire inventory first, never apply without a plan, and always verify after a change.
- Treat unknown, partial, stale, ambiguous, or tampered state as a blocking condition.
- Never add uninstall, elevation, reboot, driver, firmware, source-addition, or arbitrary-command paths without a separately reviewed versioned design.
- Never silently install dependencies. Runtime YAML support is detected and installation guidance is reported; CI installs development dependencies explicitly.
- Tests and CI must use injected adapters/fixtures and must never mutate real packages.
- Never add or invoke administrator elevation, package uninstall, driver, BIOS, or firmware operations.
- Do not persist raw host/user values, secrets, credentials, or unredacted command diagnostics.
- **AI agents may inspect, explain, and prepare changes, but may not approve plans or bypass the interactive typed-digest approval step.** Approval is a human-only action.
- Do not use force/bypass switches, approval environment variables, or co-located approval artifacts.
- Preserve unrelated changes and document limitations rather than claiming unsupported behavior.
- Run workspace commands must keep all artifacts inside the run directory and reject traversal and reparse points.
- Manager ACL trust is conservative; unknown ACL state remains blocked rather than being silently trusted.
