# Release checklist

- Confirm that `LICENSE` retains the approved `Copyright (c) 2026 Ludi` notice.
- Run schema/sample validation, module import, PSScriptAnalyzer, all Pester suites, and fixture-only CLI `-WhatIf` smoke.
- Confirm CI uses official GitHub actions, a Windows runner, explicit dev dependency installation, and no real package mutation.
- Review exported commands and public docs for unsupported claims, approval bypasses, secrets, local paths, uninstall/elevation/reboot verbs, and skipped tests.
- Record known limitations and dependency/license changes in `CHANGELOG.md`.
