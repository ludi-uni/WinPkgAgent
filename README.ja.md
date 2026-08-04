# winpkg-agent

`winpkg-agent` は PowerShell 7.4 以降で WinGet と Scoop を人間の承認付きで扱うためのモジュールです。処理順序は **inventory → plan → approval → apply → verify** に固定されています。

## 安全に関する重要な警告

> **このツールはパッケージの導入・更新やシステム状態の変更を補助します。適用前に生成された計画を確認し、重要なデータと設定をバックアップしてください。**

v0.1 は `state: present` のみを対象とし、アンインストール・昇格・再起動・ドライバー・ファームウェアの経路を持ちません。状態が不完全、古い、曖昧、または改ざんされている場合はフェイルクローズします。計画と `-WhatIf` は読み取り専用で、テストは実際のパッケージを変更しません。

安全性を優先したモジュールです。README の例だけで対応機能を判断せず、スキーマ、ポリシー、テストを正としてください。

## 目的と非目標

本ツールはパッケージマネージャーの代替ではなく、安全な調整層です。WinGet はデスクトップアプリ、Scoop は CLI・開発・ポータブルツールを担当します。削除、source追加、権限昇格、再起動、ドライバー・BIOS・ファームウェア操作、自動ロールバックは行いません。

各パッケージには `source` と `category` の明示が必要です。Scoopのinventoryとinstallは対応しますが、公式updateコマンドでは承認した正確な版を固定できないため、v0.1ではScoop upgradeをブロックします。

## 要件と依存関係

PowerShell 7.4 以降が必要です。YAML パーサーは明示的にインストールします（自動インストールはありません）。

```powershell
Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser
Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1
```

WinGet と Scoop の状態・契約は各マネージャーが管理します。承認は人間による対話的なダイジェスト入力であり、AI エージェントは計画を準備できても承認できません。

## クイックスタート

```powershell
Test-WpaEnvironment
Get-WpaInventory -OutputPath ./artifacts/inventory.json
New-WpaPlan -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.default.yaml -InventoryPath ./artifacts/inventory.json -OutputPath ./artifacts/plan.json -MarkdownPath ./artifacts/plan.md
Show-WpaPlan -PlanPath ./artifacts/plan.json
# ここで人間が計画を確認し、対話端末で Approve-WpaPlan を実行します。
Invoke-WpaPlan -PlanPath ./artifacts/plan.json -ApprovalPath ./artifacts/plan.approval.json -PolicyPath ./config/policy.default.yaml -WhatIf
```

`-WhatIf`では変更アダプターを呼びません。承認は計画ダイジェストへの明示的同意であり、本人認証やロールバック保証ではありません。

詳細は [docs/architecture.ja.md](docs/architecture.ja.md)、[docs/safety.ja.md](docs/safety.ja.md)、[docs/usage.ja.md](docs/usage.ja.md) を参照してください。

依存関係、開発方法、脆弱性報告は [CONTRIBUTING.md](CONTRIBUTING.md)、[AGENTS.md](AGENTS.md)、[SECURITY.md](SECURITY.md) に記載しています。
