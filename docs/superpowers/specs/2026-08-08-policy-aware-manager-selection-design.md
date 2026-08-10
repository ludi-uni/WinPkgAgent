# Policyファイルによるmanager切り替え設計

## 目的

実行環境ごとに許可されたパッケージmanagerだけを使えるようにする。

代表例は次の2環境である。

- Codex実行環境: WinGetが見えない、または実行を許可されないためScoopだけを使う
- 通常のWindowsデスクトップ: WinGetとScoopの両方を使う

切り替えは環境の自動判定やポリシー回避ではなく、実行時に明示したpolicyファイルで行う。

## 背景と現状

現在のpolicy schemaには`allowedManagers`があり、plan評価ではmanager未許可を`MANAGER_NOT_ALLOWED`としてブロックできる。一方で、inventoryは`Get-WpaInventoryAggregate`内でWinGetとScoopを常に列挙し、`Get-WpaInventory`はpolicyを受け取らない。

そのため、CodexでScoopだけを使いたい場合でもWinGetの検出・inventoryを試行し、部分inventoryやアクセス拒否の警告が発生する。また`Invoke-WpaPlan`の再inventoryもpolicyを渡していないため、plan時とapply時でmanager scopeを一致させられない。

対象となる既存の境界は次の通りである。

- policyの許可manager: `schemas/policy.schema.json` と `config/policy.default.yaml`
- managerごとのinventory: `src/WinPkgAgent/Private/Inventory/Aggregator.ps1`
- public inventory: `src/WinPkgAgent/Public/Get-WpaInventory.ps1`
- policy評価: `src/WinPkgAgent/Private/Planning/Evaluation.ps1`
- plan/apply時のpolicy hashと再inventory: `src/WinPkgAgent/Public/New-WpaPlan.ps1`、`src/WinPkgAgent/Public/Invoke-WpaPlan.ps1`
- run workspaceのpolicyコピー: `src/WinPkgAgent/Private/Workspace.ps1`

## 設計上の決定

### 1. policyファイルを唯一の切り替え単位にする

policyの継承、overlay、Codex環境の自動判定は追加しない。利用者は同じmanifestに対して、実行環境に対応するpolicyを明示する。

```text
config/policy.codex.yaml
config/policy.desktop.yaml
config/policy.default.yaml
```

`policy.default.yaml`は既存互換のdesktop向けpolicyとして残す。

### 2. inventoryをpolicy-awareにする

`Get-WpaInventory`に`-PolicyPath`を追加し、policyで許可されたmanagerだけをinventory対象にする。`-PolicyPath`は必須とする。policyを指定しないinventoryを残すと、実行者が意図せず禁止managerを試行するためである。

選択されたmanagerがinventoryに成功した場合、manager scope内の全managerが成功していればinventory statusは`success`になる。対象managerの一部が失敗した場合は`partial`、全対象が失敗した場合は`failed`とする。許可されていないmanagerはinventoryに含めず、実行もしない。

内部の`Get-WpaInventoryAggregate`はmanager一覧を引数で受け取り、従来の固定`@('winget','scoop')`ループをやめる。manager adapterは許可された名前についてだけ呼び出す。既存のfixture向け内部テストは、明示的に両managerを渡すことで従来の集約挙動を検証できる。

inventory artifactにはpolicyとの対応を残すため、次のフィールドを追加する。

```json
{
  "schemaVersion": 2,
  "policyHash": "64 lowercase hex characters",
  "managerScope": ["scoop"]
}
```

`policyHash`は読み込んだpolicyのcanonical hash、`managerScope`はpolicyの`allowedManagers`をソートした値である。inventory state hashにもscopeを含め、異なるpolicyで作ったinventoryを同じplanに流用できないようにする。既存のschemaVersion 1 inventoryは再生成を要求し、黙ってpolicy scopeを推測しない。

### 3. policy判定をmanager availability判定より先に行う

plan評価では各manifest packageについて、次の順序で判定する。

1. managerがpolicyの`allowedManagers`に含まれない場合: `blocked / MANAGER_NOT_ALLOWED`
2. managerが許可されているがinventory scopeに含まれない場合: `blocked / MANAGER_UNAVAILABLE`またはscope欠落の検証エラー
3. managerが許可され、inventoryが`success`である場合: 通常のinstall/no-op/upgrade判定

これにより、Codex policyでWinGet packageが宣言されていても、WinGet fingerprint不足による例外に先行して「policyで禁止されている」と表示できる。

禁止managerのpackageをScoopへ自動変換したり、同一ソフトウェアらしさだけで別managerへ再割当てしたりしない。manager ownershipはmanifestの明示宣言を正とする。

### 4. applyとverificationも同じpolicy scopeを使う

`Invoke-WpaPlan`は、指定された`-PolicyPath`を読み込んだ後、次のすべてのinventory取得に同じpolicyを渡す。

- apply前のcurrent inventory
- apply後のverification inventory

`Resume-WpaVerification`にも`-PolicyPath`を追加し、reboot後のinventoryを同じscopeで取得する。これによりCodex policyでapplyしたplanが、resume時だけWinGetを試行することを防ぐ。

policy hash、inventory hash、manager fingerprint、approval digestの既存再検証は維持する。policyを変更した場合は従来通りplanを再生成し、既存approvalを利用できない。

### 5. run workspaceはpolicyをそのまま伝播する

`New-WpaRun`は既にpolicyをrun workspaceへコピーしているため、run生成時のinventory取得にもrun内のpolicy pathを渡す。`Invoke-WpaRun`と`Resume-WpaVerification`はrun内の同じpolicy artifactを使う。

CLIの`inventory`、`environment`、`resume-verify`にも`-PolicyPath`を伝播させ、手動フローとrunフローでmanager scopeを一致させる。

## policy例

### Codex用

```yaml
schemaVersion: 1
allowInstall: true
allowUpgrade:
  - patch
  - minor
allowedManagers:
  - scoop
allowedSources:
  - main
  - extras
  - versions
protectedPackages: []
dangerousCategories:
  - driver
  - bios
  - uefi
  - firmware
allowUninstall: false
requireApproval: true
approvalValidityMinutes: 30
rejectStateChanges: true
maxOperations: 20
operationTimeoutSeconds: 600
rebootHandling: record-only
unknownVersionHandling: block
```

### desktop用

`config/policy.default.yaml`をdesktop向けの標準policyとして使用し、`allowedManagers`に`winget`と`scoop`を含める。WinGetのsourceを許可する場合だけ`allowedSources`に`winget`を含める。

## CLIとPowerShell API

推奨する呼び出し順序は次の通りである。

```powershell
pwsh ./scripts/winpkg-agent.ps1 environment `
  -PolicyPath ./config/policy.codex.yaml

pwsh ./scripts/winpkg-agent.ps1 inventory `
  -PolicyPath ./config/policy.codex.yaml `
  -OutputPath ./artifacts/codex-inventory.json

pwsh ./scripts/winpkg-agent.ps1 plan `
  -ManifestPath ./config/packages.example.yaml `
  -PolicyPath ./config/policy.codex.yaml `
  -InventoryPath ./artifacts/codex-inventory.json `
  -OutputPath ./artifacts/codex-plan.json
```

desktopでは同じmanifestに対して`policy.default.yaml`または`policy.desktop.yaml`を渡す。

`Test-WpaEnvironment -PolicyPath`はpolicyのallowedManagersだけを検査し、`ready`は許可managerがすべて利用可能な場合だけtrueにする。manager一覧のうちpolicy対象外のmanagerは未評価として扱い、対象外managerの検出を理由にreadyをfalseへ変えない。

## データフロー

```text
policy file
    |
    +--> validate policy and calculate policyHash
    |
    +--> managerScope = allowedManagers
              |
              +--> environment: allowed managers only
              +--> inventory: allowed adapters only
              +--> plan: disallowed packages become blocked
              +--> apply/verify: same policy-scoped inventory
```

policy fileを変えた場合、policy hashとinventory scopeが変わる。旧plan、旧approval、旧inventoryをそのまま使わず、同じpolicy fileでinventoryとplanを作り直す。

## エラー処理と安全境界

- policyが存在しない、schema不正、`allowedManagers`が空の場合は、managerを一つも呼ばずに失敗する
- 許可されていないmanagerは`MANAGER_NOT_ALLOWED`としてplanに残す
- 許可managerがCodexから見えない場合は`MANAGER_UNAVAILABLE`またはinventoryのpartial/failedとして残す
- WinGetを許可するpolicyに切り替えたからといって、CodexのsandboxやOS policyを回避しない
- source agreements、execution policy、PATH、権限、App Installerの設定を自動変更しない
- `-WhatIf`、preflight、approval digest、manager fingerprintの既存安全境界を変更しない
- managerの自動代替、uninstall、elevation、任意コマンド実行は対象外

## 互換性と移行

これは明示的policy指定を前提とする動作への変更である。次を行う。

1. `config/policy.codex.yaml`と`config/policy.desktop.yaml`を追加する
2. README、README.ja.md、docs/usage、docs/architecture、docs/troubleshootingにpolicy選択を記載する
3. inventory schemaをversion 2へ更新する
4. 既存inventory artifactは再生成を要求する
5. `Get-WpaInventory`、CLI inventory、run workspace、apply、verification、resumeの各呼び出しへpolicy pathを通す
6. 既存の`policy.default.yaml`はdesktop向けの互換入口として残す

manifestのpackage schemaやmanager名は変更しない。既存manifestは、選択したpolicyで許可されないpackageがblockedとして表示されるだけであり、自動的に書き換えない。

## テスト設計

実在のWinGet/Scoopは呼ばず、既存のadapter fixture/mockを使う。

### Policyとinventory

- `allowedManagers: [scoop]`でScoop adapterだけが呼ばれ、WinGet adapterが呼ばれない
- `allowedManagers: [winget]`でScoop adapterだけが呼ばれない
- allowed managerが1つだけ成功した場合、そのscopeではinventoryが`success`になる
- allowed managerの一部失敗が`partial`、全失敗が`failed`になる
- 空のallowedManagers、不正なmanager、schemaVersion 1 inventoryをfail closedする
- inventoryの`policyHash`、`managerScope`、state hashがpolicy変更を反映する

### Plan

- policy不許可managerはfingerprint不足より先に`MANAGER_NOT_ALLOWED`になる
- policy許可managerのscope不足は安全側に失敗する
- 不許可managerのpackageを別managerへ自動変換しない
- 同じmanifestをCodex policyとdesktop policyで評価すると、manager availabilityとblocked理由が期待通りに変わる

### Apply / verify / run

- `Invoke-WpaPlan`のcurrent inventoryとafter inventoryが指定policy pathを受け取る
- `Resume-WpaVerification`がrunまたは明示policy pathを使う
- Codex policyのapply/preflightでWinGet processが呼ばれない
- policy hash drift、inventory hash drift、manager fingerprint driftは既存通りmutation前に拒否する
- CLI fixture smoke testでpolicy pathがenvironment、inventory、plan、invokeに伝播する

## 実装完了条件

- policyファイルを明示的に差し替えるだけでmanager scopeを切り替えられる
- Codex policyではWinGetの検出・inventory・apply・verificationを試行しない
- desktop policyではWinGetを許可managerとして扱える
- 不許可managerは明示的なblocked actionとしてplanに残る
- 自動fallback、policy回避、approval bypass、PATH変更がない
- inventory/plan/apply/verify/runのpolicy hashとscopeが一致する
- 関連Pester、schema検証、fixture-only CLI smoke testが通る

## 対象外

- Codexか通常端末かの自動判定
- policyファイルの継承・overlay
- Intune、Company Portal、社内配布基盤など新しいmanager adapter
- WinGet packageをScoop packageへ自動移行する機能
- policyによるexecution policy変更、管理者昇格、sandbox回避
