# 使い方

`Get-WpaInventory` → `New-WpaPlan` → `Approve-WpaPlan` → `Invoke-WpaPlan` → 検証の順で実行します。最初は必ず fixture に対する `-WhatIf` を行い、計画を人間が確認してから適用してください。inventoryには必ず `-PolicyPath` を指定します。

正確なパラメーターは公開コマンドのヘルプとスキーマを正とします。YAML 依存関係が無い場合も自動インストールは行われません。

`Test-WpaEnvironment` の `managers.scoop` が `false` の場合は、[Scoop公式手順](https://github.com/ScoopInstaller/Install#installation)を確認し、通常の非管理者PowerShellでScoopを導入してください。PowerShellを開き直した後、inventoryとplanを作り直します。ツールはScoopを自動導入しません。

policyはホストやCodexから推測せず、明示的に選択します。CodexでScoopだけを使うscopeには `./config/policy.codex.yaml`、デスクトップのWinGet+Scoopには `./config/policy.desktop.yaml` または `./config/policy.default.yaml` を使い、environment、inventory、plan、apply、検証に同じpolicyを渡します。inventoryはschema v2の `policyHash` と `managerScope` を持つため、schema v1またはscopeなしの成果物はplanの前に再生成します。不一致は `INVENTORY_SCOPE_MISMATCH` で拒否されます。

実行環境は `powershell.exe` ではなく、PowerShell 7.4以降の `pwsh.exe` を使用してください。パス解決が不安定な場合は、絶対パスで実行します。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File ./scripts/winpkg-agent.ps1 environment
```

既存パッケージを管理候補に取り込む場合は、inventoryから保留中の候補を生成します。候補はmanager exportで検出されたパッケージを含みますが、元の導入経路を証明するものではありません。`source`、`category`、再インストール影響を人間が確認するまで、active manifestへ昇格させないでください。

```powershell
Get-WpaInventory -PolicyPath ./config/policy.default.yaml -OutputPath ./artifacts/migration-inventory.json
Export-WpaManifestCandidate `
  -InventoryPath ./artifacts/migration-inventory.json `
  -OutputPath ./artifacts/migration-candidate.yaml
```

再起動後のCLI検証でもpolicyを明示します。

```powershell
pwsh ./scripts/winpkg-agent.ps1 resume-verify `
  -PlanPath ./artifacts/plan.json `
  -ApplyResultPath ./artifacts/apply-result.json `
  -PolicyPath ./config/policy.default.yaml `
  -VerifyOutputPath ./artifacts/verify-result.json `
  -WhatIf
```

WinGetのexportに含まれないインストール済み項目も、別の保留レビュー成果物として確認できます。これはactive manifestではありません。ARP/MSIX IDやsource不明項目は手動マッピングのままになり、自動的にインストール候補へ昇格しません。

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File ./scripts/winpkg-agent.ps1 unmanaged-candidate `
  -InventoryPath ./artifacts/migration-inventory.json `
  -OutputPath ./artifacts/unmanaged-candidate.json
```

一覧形式が未知または途中で壊れている場合は、推測せず `partial` / `failed` として記録します。WinGetにはsource同意やパッケージ変更の引数を渡しません。

`policy.codex.yaml` でWinGetを宣言した項目は `MANAGER_NOT_ALLOWED` でblockedになり、Scoopへfallback/remapしません。PATH、実行ポリシー、App Installer/OS policyを変更せず、昇格、manager導入、承認バイパスも行いません。`MANAGER_UNAVAILABLE` は許可managerの利用不可、`INVENTORY_SCOPE_MISMATCH` はpolicy hashまたはscopeの不一致です。

CLI終了コードは、`0` が成功または `-WhatIf`、`1` がコマンド／事前検証エラー、`2` が検証結果不正、`3` が部分適用失敗、`4` が適用後検証失敗、`5` が再起動待ちです。ツール自身は再起動しません。
