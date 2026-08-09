# Fail-closed previewコマンド設計

## 目的

環境診断、インベントリ取得、計画生成、要約表示を1つのCLIコマンドにまとめる。利用者がWinGetまたはScoopのポリシーを明示して、安全な計画をすぐ確認できるようにする。

この機能は承認やパッケージ変更を自動化しない。対話式typed-digest承認とapplyは、既存の別コマンドとして維持する。

## 背景

現在の安全なrunフローは、少なくとも`new-run`と`show-run`を個別に実行する必要がある。policy-aware manager選択により環境ごとにmanager scopeを切り替えられるようになったが、利用者は実行順序、run path、次の承認コマンドを自分で組み立てなければならない。

また、現在の`New-WpaRun`はrunディレクトリを作成してpolicyとmanifestをコピーした後にinventoryを取得する。環境またはinventoryが信頼できない場合でも、部分的なrunディレクトリが残り得る。新しい入口はこの状態を成功したpreviewとして見せてはならない。

## 採用する方式

CLIに`preview`コマンドを追加する。

```powershell
pwsh ./scripts/winpkg-agent.ps1 preview `
  -ManifestPath ./config/packages.example.yaml `
  -PolicyPath ./config/policy.codex.yaml `
  -WorkspacePath ./.wpa
```

`preview`は既存のrunモデルを利用し、次の処理だけを行う。

1. manifestとpolicyを読み取り、schemaと参照profileを検証する
2. policyで許可されたmanagerだけを対象に環境診断する
3. 同じpolicyでinventoryを取得し、信頼可能か判定する
4. 同じmanifest、policy、inventory snapshotからplanを生成する
5. 完成したrun artifactをrun workspaceへ公開する
6. planの件数、ブロック理由、run path、次の人間用コマンドを表示する

`preview`は`Approve-WpaRun`、`Approve-WpaPlan`、`Invoke-WpaRun`、`Invoke-WpaPlan`、manager mutation adapterを呼ばない。

## CLI境界

### 引数

`preview`は次を受け取る。

- `-ManifestPath`: 必須
- `-PolicyPath`: 必須
- `-WorkspacePath`: 任意。既存の`new-run`と同じ既定値`./.wpa`
- `-WhatIf`: 任意。run作成予定だけを返し、artifactを作成しない

managerの自動選択、policy自動検出、承認継続、apply継続のswitchは追加しない。

### 出力

成功時は機械処理可能な単一のsummary objectを返す。

```text
status: ready | blocked | what-if
runId: <run id or null>
runPath: <run path>
actionCount: <number>
blockedCount: <number>
warningCount: <number>
nextCommand: pwsh ./scripts/winpkg-agent.ps1 approve-run -RunPath '<run path>'
```

`blocked`はplan自体の生成に成功したが、1件以上の`blockedOperations`が含まれることを示す。ブロックされていないactionがある場合、人間はplanを確認したうえで既存の承認フローへ進める。`preview`自身は承認を開始しない。

`runPath`と`nextCommand`はコンソール出力にだけ含め、run artifactへ新しいraw host/user値として永続化しない。

### 終了コード

- `0`: preview生成成功。ブロック項目なし、または`-WhatIf`成功
- `1`: manifest、policy、環境、inventory、plan、workspace公開のいずれかが失敗。完成runなし
- `2`: preview生成成功。ただしplanにブロック項目あり

既存のapply/verification終了コード`3`から`5`は変更しない。

## 信頼性判定

### runを作成しない条件

次のいずれかではfail closedし、最終run pathを公開しない。

- manifest、policy、profileの読取りまたはschema検証に失敗
- policyの`allowedManagers`が不正または空
- `Test-WpaEnvironment -PolicyPath`の`ready`がfalse
- inventory全体のstatusが`partial`または`failed`
- inventoryのpolicy hashまたはmanager scopeが一致しない
- manager fingerprint evidenceが不足または不正
- plan生成またはrun artifact検証に失敗
- workspace pathにtraversal、境界外path、reparse point、競合run IDがある

unknown、partial、stale、ambiguousなinventoryはpreview成功として扱わない。manager processのstderrや生の診断値をartifactへ保存しない既存方針も維持する。

### runへ保存するブロック

信頼可能なinventoryからplanを生成でき、個別packageだけがpolicyやmanifest条件で拒否された場合はrunを保存する。代表例は次の通りである。

- `MANAGER_NOT_ALLOWED`
- protected package、危険カテゴリ、許可外source
- unknown version policyによる拒否

これらは`plan.json`と`plan.md`の`blockedOperations`へ理由付きで残す。別managerへの自動変換や自動fallbackは行わない。

## run生成の原子性

`New-WpaRun`のpublic command名と引数、export一覧は変更しない。ただし内部処理を次の二段階へ整理する。

### 1. prepare段階

workspaceを変更せず、manifest、policy、profile、environment、inventory、planを検証する。plan object生成部分はファイル書込みから分離したprivate helperへ抽出し、`New-WpaPlan`とrun prepare処理で共有する。

inventoryは一度だけ取得し、その同一snapshotをplanとrun artifactに使用する。診断後に別inventoryを取り直して異なる状態をplanへ混在させない。

### 2. publish段階

prepare成功後だけ、`<workspace>/runs`配下へ一意なstaging runディレクトリを作る。固定artifact名でmanifest、policy、profile、inventory、plan、plan markdown、run metadataを書き込み、schemaと固定pathを再検証してから最終run IDのディレクトリへ公開する。

publish失敗時は、この呼出しが新規作成したstagingディレクトリだけを削除する。削除前に次をすべて検査する。

- stagingの親が解決済み`runs`ディレクトリと完全一致する
- staging名が今回生成した一意な名前と完全一致する
- traversalまたはreparse pointがない
- 既存runやworkspace rootを対象にしていない

このcleanupはパッケージ削除や任意path削除ではなく、未公開の自前staging artifactだけに限定する。cleanup自体に失敗した場合は成功を返さず、staging残留を明示的に報告する。

## policy伝播

次の全段階で、CLIから渡された同一policy内容を使用する。

```text
preview
  -> manifest/policy validation
  -> Test-WpaEnvironment(policy)
  -> Get-WpaInventory(policy)
  -> plan evaluation(policy + same inventory snapshot)
  -> run-local policy artifact
```

Codex用policyがScoopだけを許可する場合、WinGetの検出、inventory、plan fingerprint、applyへの接続は試行しない。desktop用policyがWinGetとScoopを許可する場合は、両方の環境診断とinventoryが成功しなければpreviewを作成しない。

WinGetやScoopが利用できない場合に、PATH、PowerShell execution policy、source agreement、App Installer、sandbox、ACLを自動変更しない。依存関係も自動インストールしない。

## 承認境界

preview成功後も、人間は別コマンドでplanを確認し、typed digestを入力する。

```powershell
pwsh ./scripts/winpkg-agent.ps1 show-run -RunPath <run-path>
pwsh ./scripts/winpkg-agent.ps1 approve-run -RunPath <run-path>
pwsh ./scripts/winpkg-agent.ps1 invoke-run -RunPath <run-path> -WhatIf
pwsh ./scripts/winpkg-agent.ps1 invoke-run -RunPath <run-path>
```

AI agentはpreview、show、説明、候補整理まで実行できるが、typed digestの入力、approval artifactの生成、applyの承認を代行しない。approval bypass用の環境変数、force switch、同居approval artifactは追加しない。

## 互換性

- `new-run`は残し、既存スクリプトとの互換入口とする
- `preview`と`new-run`は同じfail-closed prepare/publish処理を共有する
- `New-WpaRun`の公開シグネチャとmodule export一覧は変更しない
- manifest、policy、inventory、plan、run schemaは変更しない
- 既存runの`show-run`、`approve-run`、`invoke-run`は変更しない
- `preview`はCLI追加であり、新しい公開PowerShell APIを追加しない

## テスト設計

実在のWinGet/Scoopや実パッケージを操作せず、注入adapter、fixture、mockだけを使用する。

### run prepare/publish

- 環境がreadyでなければinventory、plan、run作成へ進まない
- inventoryが`partial`または`failed`なら最終runとapproval artifactが存在しない
- schema不正、policy scope不一致、fingerprint不足でも最終runが存在しない
- 信頼可能なinventoryでは、同じsnapshotからplanとinventory artifactを生成する
- publish中の失敗は今回のstagingだけをcleanupし、既存runを変更しない
- traversal、reparse point、競合run IDを拒否する

### 個別ブロック

- policy不許可managerを含むmanifestでも、信頼可能な許可manager inventoryがあればrunを保存する
- blocked reason、blocked count、終了コード`2`が一致する
- blocked packageを別managerへ自動変換しない

### CLI

- `preview`がmanifest、policy、workspaceをrun生成へ伝播する
- 成功時に単一summary objectと`approve-run`の次コマンドを返す
- `-WhatIf`ではartifact、approval、apply結果を作成しない
- `preview`経路でapproval/apply関数とmutation adapterが呼ばれない
- 既存`new-run`、`approve-run`、`invoke-run`と終了コード`3`から`5`が回帰しない

## ドキュメント

README、README.ja.md、英日usage、troubleshootingへ次を追加する。

- Codex/Scoop policyとdesktop policyそれぞれの`preview`例
- `0`、`1`、`2`の終了コード
- blocked previewはrunを保存するが、自動承認しないこと
- fatal trust failureでは完成runを残さないこと
- 次の手動手順が`show-run`、`approve-run`、`invoke-run -WhatIf`、`invoke-run`であること

## 実装完了条件

- 1コマンドで信頼可能なinventoryとplanを持つrunを生成し、要約を確認できる
- environmentまたはinventoryが信頼できない場合、完成runを生成しない
- 個別packageのblocked reasonをrunに保持する
- policy scopeが環境診断、inventory、plan、run artifactで一致する
- preview経路からapproval、apply、elevation、uninstall、source追加を実行できない
- 新しい公開PowerShell APIまたはschema変更がない
- fixture-onlyの関連Pester、CLI smoke、repository定義のCI相当検証が通る

## 対象外

- 承認とapplyを含む`safe-run`コマンド
- managerまたはpolicyの自動選択
- WinGetからScoop、ScoopからWinGetへの自動移行
- source追加、依存関係導入、PATH変更、管理者昇格
- uninstall、driver、BIOS、UEFI、firmware操作
- GUI、対話wizard、常駐監視

## 却下した代替案

### 承認・適用まで継続する`safe-run`

操作数は減るが、previewと人間承認の境界が不明瞭になるため採用しない。

### 外部wrapperで既存コマンドを連結する

変更量は少ないが、policy伝播、run path計算、終了コード、失敗cleanupがCLI外へ重複する。安全性を一箇所で検証しにくいため採用しない。

### 失敗も診断runとして保存する

部分artifactを正常なpreviewと取り違える危険がある。環境またはinventoryが信頼できない場合は完成runを作らず、コンソールへsanitized reasonだけを返す。
