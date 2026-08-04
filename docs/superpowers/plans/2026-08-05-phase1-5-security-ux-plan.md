# WinPkgAgent フェーズ1〜5実装計画

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** WinPkgAgentのimport副作用、manager実体差し替え、apply/verify混在schema、外部出力漏えい、approval前WhatIfの問題を、既存の安全境界を維持したまま修正する。

**Architecture:** 既存のpublic commandとprivate helperを維持し、manager executable context/fingerprintを共通helperとして追加する。inventory/planで保存したfingerprintをapply直前に再取得して比較し、差異時はmutation前に停止する。apply/verify resultは別schemaに分離し、process本文はメモリ内でhash・長さ・redacted summaryへ変換する。Invoke-WpaPlanはapproval不要の読み取り専用Preflight parameter setと、approval必須のApply parameter setに分ける。

**Tech Stack:** PowerShell 7.4+, Pester 5.6.1, PSScriptAnalyzer 1.25.0, powershell-yaml 0.4.12, JSON Schema draft 2020-12, System.Diagnostics.ProcessStartInfo.ArgumentList,既存atomic write helper。

## Global Constraints

- import時に環境変数、PATH、ファイル、設定を変更しない。
- WinGetとScoopは解決済み絶対パスで起動する。
- 任意コマンド文字列、shell経由の文字列連結、Invoke-Expression、iex、cmd /c、powershell -Commandを追加しない。
- package manager引数は配列で渡す。
- WhatIfでは変更系adapter、apply journal、apply/verify artifactを呼ばない、または書かない。
- unknown/partial/tampered状態は推測せずフェイルクローズする。
- 実パッケージを変更せず、adapterはfixtureまたはmockでテストする。
- 通常artifactに生のresolvedPath、stdout、stderrを保存しない。
- 通常applyには人間のtyped-digest approval artifactを必須とする。
- 変更前に既存テストを実行し、変更後にPSScriptAnalyzer、Pester、fixture-only CLI smoke testを実行する。

---

### Task 1: ベースライン固定

**Files:** Test tests/ and scripts/winpkg-agent.ps1; review git status and recent log.

**Interfaces:** 既存Pester configurationとfixture-only CLIを使用し、変更前の結果を後続taskの比較基準にする。

- [ ] 変更前の作業ツリーと対象テストを記録する。
    git status --short
    git log -3 --oneline
    Get-ChildItem tests -Recurse -File
- [ ] 既存Pesterを実行し、失敗テスト名とexit codeを記録する。
    $config = New-PesterConfiguration
    $config.Run.Path = './tests'
    $config.Run.Exit = $true
    Invoke-Pester -Configuration $config
- [ ] fixture-only WhatIf smokeを実行し、実パッケージ変更とartifact有無を記録する。
    ./scripts/winpkg-agent.ps1 plan -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.default.yaml -InventoryPath ./examples/inventory.sample.json -OutputPath ./TestResults/baseline-whatif-plan.json -WhatIf
- [ ] ベースライン後に作業ツリーを再確認する。
    git status --short

---

### Task 2: PATH副作用除去と絶対パス固定

**Files:** Modify src/WinPkgAgent/WinPkgAgent.psm1, src/WinPkgAgent/Private/Adapters/ExecutableResolution.ps1, Winget.ps1, Scoop.ps1, tests/Contract/Manager.Tests.ps1; create tests/Unit/ImportSideEffects.Tests.ps1.

**Interfaces:** Resolve-WpaManagerExecutable -Manager winget|scoopをmanager processのFileNameへ渡す。

- [ ] import side-effect regression testを追加する。import前後のPathが完全一致し、Invoke-WpaProcessが0回、artifactが作成されないことをmockで固定する。
- [ ] 旧実装でテストを実行し、Path変更がInitialize-WpaManagerPathのimport呼出しに由来することを確認する。
- [ ] WinPkgAgent.psm1からInitialize-WpaManagerPathの自動呼出しを削除し、不要になった関数を削除する。
- [ ] Invoke-WpaProcessのFileNameがfully-qualified pathでない場合に拒否する。inventory、install、upgradeの各adapterで解決済みpathを一貫して使用する。
- [ ] 相対path拒否、absolute executable、manager action/inventoryが解決済みpathを使うケースをfixture/mockで追加する。
- [ ] 近接テストを実行する。
    Invoke-Pester -Path ./tests/Unit/ImportSideEffects.Tests.ps1,./tests/Contract/Manager.Tests.ps1 -Output Detailed
- [ ] 差分確認後にコミットする。
    git add src/WinPkgAgent tests/Unit/ImportSideEffects.Tests.ps1 tests/Contract/Manager.Tests.ps1
    git commit -m phase1-remove-import-path-side-effect

---

### Task 3: manager fingerprintとplan/apply比較

**Files:** Modify ExecutableResolution.ps1, Aggregator.ps1, Get-WpaInventory.ps1, New-WpaPlan.ps1, Invoke-WpaPlan.ps1, Canonical.ps1, schemas/inventory.schema.json, schemas/plan.schema.json; create tests/Unit/ManagerFingerprint.Tests.ps1; modify tests/Unit/ApprovalExecution.Tests.ps1.

**Interfaces:** Add Get-WpaManagerFingerprint -Manager name -Executable absolutePath. Its artifact representation contains manager, pathHash, fileSha256, fileVersion, lastWriteTimeUtc, fileLength, isReparsePoint, signatureStatus, signerSubject, and aclAssessment; it never contains resolvedPath.

- [ ] field presence、64文字小文字hash、raw path不在、same-file equality、content/metadata mismatchのcontract testsを書く。
- [ ] WinGetのinvalid/unknown/unavailable Authenticodeとreparse rejectionをテストする。
- [ ] Scoopのsimple .cmd shim forwardingとcomplex/unknown shim partial handlingをテストする。
- [ ] old implementationで新testsが失敗することを確認する。
- [ ] absolute pathを正規化してpathHashを計算し、SHA-256、file version、UTC last-write、length、reparse、signature、signerを収集する。signature取得不能は成功扱いにしない。
- [ ] Scoopは既知の単純転送形式だけを解析し、shellで解釈せず、shim/targetのhashとreparse状態を収集する。不明形式はMANAGER_FINGERPRINT_UNAVAILABLEにする。
- [ ] inventory manager recordとplanへfingerprint snapshotを追加し、plan hash入力にも含める。取得不能managerのmutating actionはblocked/unknownにする。
- [ ] mutation adapter前にplan fingerprintと再取得fingerprintを比較する。差異、署名不正、path trust failure、取得不能をMANAGER_EXECUTABLE_CHANGED、MANAGER_SIGNATURE_INVALID、MANAGER_PATH_UNTRUSTED、MANAGER_FINGERPRINT_UNAVAILABLEで停止する。
- [ ] 近接テストを実行する。
    Invoke-Pester -Path ./tests/Unit/ManagerFingerprint.Tests.ps1,./tests/Unit/ApprovalExecution.Tests.ps1 -Output Detailed
- [ ] 差分確認後にコミットする。
    git add src/WinPkgAgent schemas tests/Unit/ManagerFingerprint.Tests.ps1 tests/Unit/ApprovalExecution.Tests.ps1
    git commit -m phase2-verify-manager-fingerprint

---

### Task 4: apply/verify schema分離

**Files:** Create schemas/apply-result.schema.json, schemas/verify-result.schema.json, tests/Unit/ResultSchema.Tests.ps1; modify DataFiles.ps1, Invoke-WpaPlan.ps1, scripts/Private/ExitCode.ps1; delete schemas/result.schema.json only after runtime参照除去.

**Interfaces:** Test-WpaDataSchema -SchemaName apply-result|verify-resultを提供し、apply/verify resultを相互に検証しない。

- [ ] apply sampleへverify固有field、verify sampleへapply固有field、両方へunknown field、不正statusを入れた拒否テストを書く。
- [ ] 両schemaにadditionalProperties false、schemaVersion、planId、status enum、ISO 8601 timestamp、operation/item required fieldsを定義する。
- [ ] apply statusはsuccess, partial-failure, what-if, failed、verify statusはsuccess, failed, indeterminate, not-run, deferred, reboot-requiredにする。
- [ ] operationはhash/length/truncatedを許可し、verify itemはdeferred/reboot reasonを許可する。apply固有fieldとverify固有fieldを混在させない。
- [ ] Invoke-WpaPlanの検証をapply-result/verify-resultへ切り替え、旧result schemaのruntime参照を除去する。
- [ ] schema/CLI近接テストを実行する。
    Invoke-Pester -Path ./tests/Unit/ResultSchema.Tests.ps1,./tests/Integration/Cli.Tests.ps1 -Output Detailed
- [ ] 旧artifactの非互換理由とplan再生成による移行方法を文書に反映する。
- [ ] taskをコミットする。
    git add schemas src/WinPkgAgent scripts/Private/ExitCode.ps1 tests/Unit/ResultSchema.Tests.ps1
    git commit -m phase3-separate-apply-verify-results

---

### Task 5: stdout/stderr最小保存と診断logging

**Files:** Modify Process.ps1, Redaction.ps1, Invoke-WpaPlan.ps1, InvokeAction.ps1, tests/Unit/Execution.Tests.ps1; create tests/Unit/DiagnosticLogging.Tests.ps1.

**Interfaces:** Invoke-WpaProcessのin-memory StdOut/StdErrを、defaultではhash/length/truncated/summaryへ、明示的DiagnosticLogging時だけbounded diagnostic textへ変換する。

- [ ] default resultがstdout/stderr本文を持たず、hash、length、truncated、exitCode、durationMs、timedOut、rebootRequired、reasonCodeを持つtestを書く。
- [ ] diagnostic modeが最大長、ANSI/control除去、token/credential redaction、profile path一般化を満たすtestを書く。
- [ ] 旧実装で回帰testが失敗することを確認する。
- [ ] sanitizerを実装し、本文を固定上限で切り、truncated flagを設定する。完全な秘密情報除去を保証する文言は追加しない。
- [ ] 成功時は本文とsummaryを保存せず、失敗時だけ短いredacted summaryを保存する。diagnostic artifactには診断logging有効化を明示し、既存atomic writerを使う。
- [ ] WhatIfでdiagnostic writerを呼ばないことをtestする。
- [ ] 近接testを実行し、コミットする。
    Invoke-Pester -Path ./tests/Unit/DiagnosticLogging.Tests.ps1,./tests/Unit/Execution.Tests.ps1 -Output Detailed
    git add src/WinPkgAgent tests/Unit/DiagnosticLogging.Tests.ps1 tests/Unit/Execution.Tests.ps1
    git commit -m phase4-minimize-command-output-artifacts

---

### Task 6: approval前Preflight/WhatIfとreboot verify境界

**Files:** Modify Invoke-WpaPlan.ps1, ExpectedState.ps1, scripts/winpkg-agent.ps1, tests/Unit/ApprovalExecution.Tests.ps1, tests/Unit/Verification.Tests.ps1, tests/Integration/Cli.Tests.ps1.

**Interfaces:** approval-free read-only Preflight/WhatIfとapproval-required Applyを追加し、reboot-required operationはdeferred verify itemを生成する。

- [ ] approval pathなしpreflightがplan/policy/inventory/environment/expiry/fingerprint/operation countを検証し、mutation adapter、journal writer、apply/verify writerを0回にするtestを書く。
- [ ] normal applyでApprovalPathなしが失敗し、Force/Approve/SkipApproval等のbypass parameterがないtestを維持する。
- [ ] exit code 3010でapply rebootRequired true、verify reboot-required、item deferred、reason REBOOT_REQUIRED_BEFORE_VERIFICATIONになるtestを書く。
- [ ] Invoke-WpaPlanをPreflight/Apply parameter setへ分ける。Preflight/WhatIfではapproval、mutation、journal、result writeを要求/実行せず、Applyではapproval digest/expiryを必ず検証する。
- [ ] CLIの既存命名を維持しつつWhatIfをpreflightへ接続する。
- [ ] 近接testを実行する。
    Invoke-Pester -Path ./tests/Unit/ApprovalExecution.Tests.ps1,./tests/Unit/Verification.Tests.ps1,./tests/Integration/Cli.Tests.ps1 -Output Detailed
- [ ] taskをコミットする。
    git add src/WinPkgAgent scripts/winpkg-agent.ps1 tests/Unit/ApprovalExecution.Tests.ps1 tests/Unit/Verification.Tests.ps1 tests/Integration/Cli.Tests.ps1
    git commit -m phase5-add-approval-free-preflight

---

### Task 7: CI供給網固定と文書整合

**Files:** Modify .github/workflows/ci.yml, README.md, README.ja.md, docs/architecture.md, docs/safety.md, docs/usage.md, docs/troubleshooting.md, SECURITY.md, CHANGELOG.md, AGENTS.md; create .github/dependabot.yml.

**Interfaces:** 文書は実装済みのparameter、schema、reason codeだけを参照し、未実装の後続フェーズを実装済みと記載しない。

- [ ] CI Actionをfull commit SHAへ固定し、元tagをコメントで残す。contents: readは維持する。
- [ ] module install後にName、Version、Repository、InstalledLocationをCI logへ出す。
- [ ] dependabotでGitHub ActionsとPowerShell依存を週次または月次更新する。
- [ ] docsへPATH不変、absolute path/fingerprint、typed digestの限界、approval-free preflight、diagnostic loggingの残存リスク、rollback/rebootなし、Scoop upgradeのv0.1 block、signature/ACL限界、旧result移行を記載する。
- [ ] diff checkと文書構文確認を実行し、taskをコミットする。
    git diff --check
    Get-Content .github/dependabot.yml -Raw | ConvertFrom-Yaml
    git add .github README.md README.ja.md docs SECURITY.md CHANGELOG.md AGENTS.md
    git commit -m phase5-fix-ci-and-security-documentation

---

### Task 8: 全体検証と境界レビュー

**Files:** Test tests/; review .github/workflows/ci.yml, git diff, git status --short.

**Interfaces:** Task 1〜7の実装をcompletion criteriaへ照合し、fresh evidenceを最終報告へ渡す。

- [ ] PSScriptAnalyzerをsrc/scriptsへ実行し、finding 0件を確認する。
- [ ] PesterをJUnit/coverage設定で実行し、exit 0と失敗0件を確認する。
- [ ] fixture-only CLI WhatIfを実行し、mutation adapter 0回とartifact未作成を確認する。
- [ ] Invoke-Expression、iex、cmd /c、powershell -Command、Start-Processの新規追加をdiffと照合する。
- [ ] PATH不変、absolute path、fingerprint差替え検出、schema分離、本文非保存、approval前preflight、WhatIf mutation 0回、reboot deferred、SHA固定、docs整合をtest名/出力へ紐付ける。
- [ ] diff check、status、stat、secret scanを実行する。raw path、token、credential、raw diagnostics、無関係な差分がないことを確認する。
- [ ] 未実行のlive integrationを成功扱いせず、見送ったフェーズと未解決制約を最終報告へ記載する。

