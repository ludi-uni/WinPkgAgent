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

`Test-WpaEnvironment` で `managers.scoop: false` と表示された場合は、inventory取得前に人間がScoopを導入してください。winpkg-agentはScoopのインストールや実行ポリシー変更を自動では行いません。通常の非管理者PowerShellで、[Scoop公式手順](https://github.com/ScoopInstaller/Install#installation)を確認したうえで実行します。

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-WebRequest https://get.scoop.sh -OutFile ./install-scoop.ps1
Get-Content ./install-scoop.ps1
./install-scoop.ps1
scoop --version
Get-Command scoop
```

マネージャーの検出は、継承した `PATH` だけに依存しません。Codex などの非対話環境では、現在ユーザーの Scoop shim と Windows App 実行エイリアスも確認します。検出した実行ファイルは inventory とパッケージ操作で共通して使用しますが、実体パスはメモリ上だけで扱い、artifact には保存しません。カスタム配置を使う場合はコマンド開始前のプロセス `PATH` に追加してください。ツールは PATH を永続変更したり、マネージャーを自動導入したりしません。

モジュールを import しても、現在の PowerShell プロセスの `PATH`、ファイル、設定は変更しません。manager 操作では解決済みの絶対パスを直接使用します。

```powershell
Import-Module ./src/WinPkgAgent/WinPkgAgent.psd1 -Force
Test-WpaEnvironment
```

## クイックスタート

```powershell
Test-WpaEnvironment
Get-WpaInventory -OutputPath ./artifacts/inventory.json
New-WpaPlan -ManifestPath ./config/packages.example.yaml -PolicyPath ./config/policy.default.yaml -InventoryPath ./artifacts/inventory.json -OutputPath ./artifacts/plan.json -MarkdownPath ./artifacts/plan.md
Show-WpaPlan -PlanPath ./artifacts/plan.json
# ここで人間が計画を確認し、対話端末で Approve-WpaPlan を実行します。
Invoke-WpaPlan -PlanPath ./artifacts/plan.json -PolicyPath ./config/policy.default.yaml -Preflight
```

`-WhatIf`では変更アダプターを呼びません。承認は計画ダイジェストへの明示的同意であり、本人認証やロールバック保証ではありません。

詳細は [docs/architecture.ja.md](docs/architecture.ja.md)、[docs/safety.ja.md](docs/safety.ja.md)、[docs/usage.ja.md](docs/usage.ja.md) を参照してください。

## PowerShell 7 の検出

WinPkgAgentが必要とするのは`pwsh.exe`（PowerShell 7.4以上）です。`powershell.exe`（Windows PowerShell 5.1）へ自動フォールバックしません。現在のCoreプロセス、PATH、標準配置、Preview、Windows Appsエイリアス、`.dotnet\tools`を順に確認します。検出時もユーザーPATH・マシンPATH・module importのPATHは変更しません。

検出できない場合は次を確認してください。

```powershell
Get-Command pwsh.exe -ErrorAction SilentlyContinue
where.exe pwsh
@(
  "$env:ProgramFiles\PowerShell\7\pwsh.exe"
  "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe"
  "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
  "$env:USERPROFILE\.dotnet\tools\pwsh.exe"
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
```

ZIP版などは、policyの`runtime.powershellPath`または`Test-WpaEnvironment -PowerShellPath 'D:\Tools\PowerShell\7\pwsh.exe'`で一時指定できます。PowerShellをインストールした後は、Codex・Terminal・VS Codeの再起動が必要な場合があります。

依存関係、開発方法、脆弱性報告は [CONTRIBUTING.md](CONTRIBUTING.md)、[AGENTS.md](AGENTS.md)、[SECURITY.md](SECURITY.md) に記載しています。
