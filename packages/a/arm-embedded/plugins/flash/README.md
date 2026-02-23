# Flash Plugin for ARM Embedded Targets

PyOCD を使用して ARM マイクロコントローラにファームウェアを書き込むプラグイン。

## 使用方法

```bash
xmake flash [options] [target]
```

## オプション

| オプション | 短縮 | 説明 | 例 |
|-----------|------|------|-----|
| `--target` | `-t` | フラッシュ対象ターゲットを指定 | `xmake flash -t stm32f4_kernel` |
| `--device` | `-d` | ターゲットデバイスを上書き | `xmake flash -d stm32f407vg` |
| `--frequency` | `-f` | SWD クロック周波数を設定 | `xmake flash -f 4M` |
| `--erase` | `-e` | プログラミング前にチップ消去 | `xmake flash -e` |
| `--reset` | `-r` | プログラミング後にリセット | `xmake flash -r` |
| `--no-reset` | `-n` | リセットしない | `xmake flash -n` |
| `--probe` | | デバッグプローブを指定 | `xmake flash --probe 0669FF37` |
| `--connect` | | 接続モード | `xmake flash --connect halt` |

## 主な機能

- **自動ターゲット選択**: 未指定時はデフォルトターゲットを使用
- **マルチプローブ対応**: 複数プローブ接続時のインタラクティブ選択
- **進捗表示**: ファイルサイズ・転送速度の表示
- **自動パックインストール**: 必要な PyOCD デバイスパックの自動検出・インストール

## マルチプローブ環境

複数のデバッグプローブが接続されている場合:

1. 全接続プローブを自動検出
2. プローブ種別、UID、ターゲット情報を一覧表示
3. 選択を促す（一致するターゲットがあればデフォルト候補を提示）
4. UID を直接指定して検出をスキップ可能:
   ```bash
   xmake flash --probe 0669FF3731324B4D43183949
   ```

## トラブルシューティング

| 問題 | 解決策 |
|------|--------|
| デバッグプローブが見つからない | USB ケーブル・ポートを確認 |
| ターゲットが応答しない | `pyocd reset -t <mcu>` を実行 |
| フラッシュ検証失敗 | `pyocd erase -t <mcu> --chip` で消去後リトライ |
| 複数プローブで誤選択 | `xmake flash --probe <unique_id>` で指定 |
| デバイスパックが未インストール | 自動インストールが有効なら自動対応。手動: `pyocd pack --install <pack>` |