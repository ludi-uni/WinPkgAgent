# WinPkgAgent フェーズ1〜5 設計

## 目的

既存の `inventory -> plan -> approval -> apply -> verify` とフェイルクローズ境界を維持したまま、以下を局所修正する。

- import時のPATH変更をなくす
- manager実行ファイルの計画時・実行時同一性を検証する
- apply結果とverify結果を別スキーマにする
- 外部コマンド出力のartifact保存を最小化する
- approval前の読み取り専用preflight/WhatIfを可能にする

対象外はrun workspace、plan表示、reboot後resume、journal拡張、manifest候補生成、初期導入UX、およびドキュメント全面改訂である。これらは後続フェーズで扱う。

## 不変の安全境界

- install/upgrade以外の変更操作、uninstall、source変更、権限昇格、再起動、driver、BIOS、firmware、任意コマンド実行は追加しない。
- 通常のapplyには、人間が作成したtyped-digest approval artifactを引き続き必須とする。
- `-WhatIf` は外部の変更系adapter、apply journal、apply result、verify resultを書かない。
- manager引数は配列で渡し、shell文字列連結、`Invoke-Expression`、`iex`、`cmd /c`、`powershell -Command`を追加しない。
- 実パッケージには接続せず、process/inventory adapterをfixtureまたはmockで検証する。

## 採用アーキテクチャ

既存のpublic commandとprivate helperを維持し、共通のmanager contextを追加する局所修正とする。manager contextは解決済み絶対パス、fingerprint、実行可能性の判定を一回の関数境界で提供する。inventoryとapplyは同じcontext生成関数を呼ぶが、計画時に保存したfingerprintとapply直前の再取得結果を比較する。

実パスは処理中のメモリにのみ保持し、artifactには保存しない。artifactには正規化絶対パスのSHA-256 (`pathHash`) とファイルメタデータを保存する。Scoop shimは単純な転送形式だけを解決し、複雑または不明な形式は推測せずpartial/failedにする。

## データフロー

### Inventory / plan

1. `Resolve-WpaManagerExecutable` がmanagerごとに既存の候補から絶対パスを得る。
2. `Get-WpaManagerFingerprint` が通常ファイル、サイズ、最終更新時刻、SHA-256、file version、reparse point、署名状態、signer subjectを収集する。
3. WinGetはAuthenticode状態を収集し、無効・不明・取得不能をmanagerのpartial/failed状態へ反映する。
4. Scoopはshim自体と単純に解決できる転送先を検査する。転送先の検証不能なshimは `MANAGER_FINGERPRINT_UNAVAILABLE` とする。
5. inventory manager recordにfingerprint（実パスを除く）を含め、planにmanagerごとのfingerprint snapshotを含める。
6. fingerprintを取得できないmanagerに対する変更actionは作成せず、blockedまたはunknownとして扱う。

### Apply / preflight

`Invoke-WpaPlan` は `Preflight` と `Apply` のparameter setを持つ。PreflightではApprovalPathを要求せず、plan/policy/inventory/environment/expiry/manager fingerprint/operation countを検証する。Applyでは従来どおりApprovalPathを要求する。

両経路で、planに記録されたfingerprintとapply直前のfingerprintを比較する。比較不能または差異がある場合は外部manager actionを呼ばず、次のreason codeを返す。

- `MANAGER_EXECUTABLE_CHANGED`
- `MANAGER_SIGNATURE_INVALID`
- `MANAGER_PATH_UNTRUSTED`
- `MANAGER_FINGERPRINT_UNAVAILABLE`

Preflightは安全なpreview結果をメモリ上で返せるが、apply artifact、verify artifact、journalは作成しない。通常applyのみが変更adapterを呼び、完了後にverifyを実施する。

## Fingerprint設計

fingerprintのartifact表現は次のフィールドを持つ。

```json
{
  "manager": "winget",
  "pathHash": "64 lowercase hex characters",
  "fileSha256": "64 lowercase hex characters",
  "fileVersion": "string or null",
  "lastWriteTimeUtc": "ISO 8601 timestamp",
  "fileLength": 123,
  "isReparsePoint": false,
  "signatureStatus": "Valid",
  "signerSubject": "string or null"
}
```

`pathHash`は正規化した絶対パスをOrdinalIgnoreCaseで正規化してSHA-256化する。`resolvedPath`自体はartifactに含めない。reparse pointは信頼済みと扱わず拒否する。ACLについては完全な安全判定を追加せず、取得できない場合は `aclAssessment: unknown` として保存するか、policyにより警告扱いに留める。

WinGetの署名検証は必須の観測値とし、署名取得不能は成功扱いにしない。Microsoft署名の完全一致を必須にするpolicy変更はこの段階では行わない。Scoopはshimと転送先のhashをfingerprintへ含め、単純な既知形式以外はpartialにする。

## Result schema分離

`schemas/apply-result.schema.json` と `schemas/verify-result.schema.json` を追加し、`result.schema.json`をruntime検証経路から外す。

apply resultは `schemaVersion`, `planId`, `status`, `startedAt`, `finishedAt`, `operations`, `rebootRequired`, `warnings` を持つ。statusは `success`, `partial-failure`, `what-if`, `failed` とする。

verify resultは `schemaVersion`, `planId`, `status`, `verifiedAt`, `items`, `rebootRequired` を持つ。statusは既存動作と互換な `success`, `failed`, `indeterminate`, `not-run`, `deferred`, `reboot-required` を許可する。apply固有フィールドをverifyへ、verify固有フィールドをapplyへ混在させず、全objectで `additionalProperties: false` を有効にする。

既存のschemaVersion 1 artifactは、旧result schemaだけに依存するものをapply対象として受け入れない。planを再生成すれば済むよう、互換性への影響と移行方法をREADME/CHANGELOGに記載する。

## 出力保存方針

通常のoperation resultには本文を保存せず、次だけを保存する。

```text
exitCode, durationMs, timedOut, rebootRequired, reasonCode,
stdoutHash, stderrHash, stdoutLength, stderrLength,
stdoutTruncated, stderrTruncated, redactedSummary
```

stdout/stderrはprocess adapterのメモリ上で扱い、hashはUTF-8本文から計算する。失敗時のsummaryは短くredact済みとし、成功時は本文もsummaryも保存しない。`-DiagnosticLogging` を明示した場合だけ、最大文字数、ANSI escape除去、制御文字除去、token/credential redaction、profile path一般化を適用した診断本文を追加する。診断artifactには診断ログを含むことと、完全な秘密情報除去を保証しないことを明記する。書き込みは既存のatomic write helperを使う。

## エラー処理

未知のmanager出力、署名状態、shim形式、fingerprint、ACL状態を推測して成功扱いしない。inventoryはpartial/failed、planはblocked/unknown、applyはfailed、verifyはindeterminateまたはdeferredへ落とす。reason codeは文字列の自由入力ではなく、実装で使用する既知値をテストで固定する。

終了コード3010などのreboot要求は、この段階では自動再起動せず、applyの `rebootRequired=true` とverifyの `reboot-required` を返す。即時verifyで完全成功を断言しない。

## テスト設計

既存テストを変更前に実行し、変更後は近接テストから順に実行する。

- import前後でPATH不変、manager process未起動、artifact未作成
- absolute executable、hash差異、reparse point、signature invalid、Scoop単純shim/複雑shim
- plan fingerprintとapply fingerprintの一致、差異、取得不能
- apply/verify schemaの正しい検証、余計なfieldと不正statusの拒否
- 通常resultにstdout/stderr本文がなく、hash/length/truncatedがある
- diagnostic modeの長さ制限、ANSI/制御文字除去、tokenとprofile pathのredaction
- approvalなしpreflight、mutation adapter未呼出し、journal/result artifact未作成
- approvalありapplyだけがmutation adapterを呼ぶ
- reboot required時のverify status
- fixture-only CLI smoke test

テストでは実在のWinGet/Scoopを呼ばず、process adapterとinventory adapterをPester mockまたはfixtureで差し替える。

## CIと文書

`.github/workflows/ci.yml` の外部ActionをフルコミットSHAへ固定し、元タグをコメントで残す。依存module導入後にName、Version、Repository、InstalledLocationをCIログへ出す。`contents: read`は維持し、write権限は追加しない。

フェーズ1〜5の実装済み範囲に合わせてREADME、README.ja.md、docs/architecture.md、docs/safety.md、docs/usage.md、docs/troubleshooting.md、SECURITY.md、CHANGELOG.md、AGENTS.mdを更新する。READMEではPATH不変、fingerprint、typed digestの限界、preflight、診断ログの残存リスク、自動rollback/rebootなし、Scoop upgradeのv0.1ブロック、署名/ACL判定の限界を明記する。

## 互換性と移行

低レベルの既存public command名と通常のinventory/plan/approval/apply/verifyフローは維持する。`Invoke-WpaPlan` にPreflight parameter setとDiagnosticLogging switchを追加する。result artifactはapply/verify分離により旧同居schemaとの互換性がないため、既存planを再生成し、既存resultを新しいapply/verify artifactへ置き換える必要がある。PATHを明示的に変更する機能は追加しない。

## 設計レビュー基準

- 変更はフェーズ1〜5に限定されている
- import時の副作用がなく、manager実行は絶対パスだけを使う
- plan/apply fingerprint比較がmutation前に行われる
- apply/verify schemaが相互に余計なフィールドを拒否する
- WhatIfがapproval不要の読み取り専用preflightになり、変更系adapterを呼ばない
- 通常artifactに外部出力本文や生の実パスを保存しない
- PSScriptAnalyzer、Pester、fixture-only smoke testの実行結果を最終報告に含める
