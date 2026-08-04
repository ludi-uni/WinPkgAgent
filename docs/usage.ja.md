# 使い方

`Get-WpaInventory` → `New-WpaPlan` → `Approve-WpaPlan` → `Invoke-WpaPlan` → 検証の順で実行します。最初は必ず fixture に対する `-WhatIf` を行い、計画を人間が確認してから適用してください。

正確なパラメーターは公開コマンドのヘルプとスキーマを正とします。YAML 依存関係が無い場合も自動インストールは行われません。

`Test-WpaEnvironment` の `managers.scoop` が `false` の場合は、[Scoop公式手順](https://github.com/ScoopInstaller/Install#installation)を確認し、通常の非管理者PowerShellでScoopを導入してください。PowerShellを開き直した後、inventoryとplanを作り直します。ツールはScoopを自動導入しません。

CLI終了コードは、`0` が成功または `-WhatIf`、`1` がコマンド／事前検証エラー、`2` が検証結果不正、`3` が部分適用失敗、`4` が適用後検証失敗、`5` が再起動待ちです。ツール自身は再起動しません。
