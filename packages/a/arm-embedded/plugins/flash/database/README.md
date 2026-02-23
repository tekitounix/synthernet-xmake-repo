# Flash Plugin Database

PyOCD 統合用のフラッシュターゲットデータベース。

## flash-targets.json

以下の情報を定義:

### 1. ビルトインターゲット

PyOCD が追加パック不要でサポートするターゲット:
- STM32F051
- STM32F103RC
- Generic Cortex-M

### 2. パック必要ターゲット

PyOCD デバイスパックのインストールが必要なターゲット:
- STM32F4 シリーズ（stm32f407vg, stm32f401re 等）
- STM32H5 シリーズ（stm32h533re 等）

各ターゲットに含まれる情報:
- `vendor`: メーカー名
- `part_number`: 型番
- `series`: デバイスシリーズ
- `families`: PyOCD 用デバイスファミリー
- `auto_install_pack`: 自動パックインストールの有効/無効
- `pack_name`: PyOCD パック名
- `pack_install_command`: 手動インストールコマンド

### 3. ターゲットエイリアス

一般的な MCU 名を PyOCD ターゲット名にマッピング:
- `stm32h533re` → `stm32h533retx`
- `stm32f407vg` → `stm32f407vgtx`
- `stm32f401re` → `stm32f401retx`

### 4. パック管理設定

- `auto_install_enabled`: 自動パックインストールの有効/無効
- `pack_install_timeout`: パックインストールのタイムアウト
- `common_packs`: よく使われる PyOCD パックの一覧

## 動作

フラッシュプラグインはターゲット書き込み時にこのデータベースを自動読み込みする。
必要なパックが未インストールの場合:

1. 不足パックを検出
2. 自動インストールを提案
3. 承認後にパックをインストール
4. フラッシュ操作を続行

## 新しいターゲットの追加

1. PyOCD のサポート状況を確認: `pyocd list --targets`
2. パックが必要なら `pack_required.targets` に追加
3. 名前が PyOCD と異なる場合はエイリアスを追加

例:

```json
"stm32g474re": {
    "vendor": "STMicroelectronics",
    "part_number": "STM32G474RE",
    "series": "STM32G4",
    "families": ["STM32G4 Series", "STM32G474"],
    "auto_install_pack": true,
    "pack_name": "stm32g4",
    "pack_install_command": "pyocd pack --install stm32g4"
}
```