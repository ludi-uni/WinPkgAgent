# アーキテクチャ

純粋なデータ処理、アダプター、成果物 I/O を分離します。公開コマンドは明示的なステージを順に実行し、隠れた可変状態を共有しません。manager policyは明示的な入力であり、ホストやCodexから暗黙に選びません。

外部プロセスは `System.Diagnostics.ProcessStartInfo` と `ArgumentList`、リダイレクトされたストリーム、構造化された終了情報、明示的なタイムアウトを持つアダプター境界だけを通ります。契約が不安定な場合は推測せず partial/failed を返します。

各manifest項目にはsourceとcategoryを必須とし、driver、BIOS、UEFI、firmwareはv0.1で緩和不能です。WinGet inventoryはsource agreementを代理承諾しません。Scoop公式updateは承認対象版を固定できないため、v0.1ではScoop upgradeをブロックし、inventoryとinstallのみを扱います。applyは各変更の直前・直後に原子的なjournalを保存します。

計画のハッシュ、承認の分離、適用前の再検証、再取得による検証については英語版を正とします。

policyに対応したinventoryはschema v2で、選択したpolicyのallowed managerから導出した `policyHash` と `managerScope` を持ちます。inventory、plan、apply、検証、resume検証には同じpolicy pathを渡します。schema v1またはscopeなしのinventoryを推測で更新せず、再生成を要求します。hashまたはscopeの不一致は `INVENTORY_SCOPE_MISMATCH`、許可されたmanagerを利用できない場合は `MANAGER_UNAVAILABLE` です。

`config/policy.codex.yaml` でWinGetを宣言したmanifest項目は `MANAGER_NOT_ALLOWED` になります。Scoopへのfallback/remapはせず、PATH、実行ポリシー、App Installer/OS policy、権限、manager導入、承認要件を変更しません。
