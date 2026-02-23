# ARM Embedded Database Files

ARM 組み込み開発用の JSON データベースファイル。
`embedded` ルール (`../xmake.lua`) が `on_load` でこれらを読み込み、データ駆動でビルド構成を行う。

## ファイル一覧

### cortex-m.json

Cortex-M コア定義:
- アーキテクチャ仕様（ARMv6-M, ARMv7-M, ARMv7E-M, ARMv8-M 等）
- GCC / LLVM コンパイラフラグ
- FPU 設定（soft, softfp, hard）
- ライブラリパス

### mcu-database.json

MCU 固有設定:
- コアタイプマッピング（e.g., `stm32f407vg` → `cortex-m4f`）
- メモリサイズ（Flash / RAM / CCM）
- メモリ開始アドレス
- ベンダー情報

### build-options.json

ビルド設定オプション:
- 最適化レベル（size, speed, balanced, debug）
- デバッグ情報レベル
- Semihosting サポート
- C++ 組み込みオプション（-fno-rtti, -fno-exceptions 等）
- ツールチェーン別リンカオプション（GCC / LLVM）
- ベアメタル固有フラグ

### toolchain-configs.json

ツールチェーン管理:
- ツールチェーンマッピング（gcc / llvm）
- パッケージパスと構造
- リンカスクリプト位置
- メモリシンボル定義

## 使用方法

`embedded` ルールが JSON ファイルを自動読み込みする。ルールロジック変更なしでターゲット定義を更新・追加可能。

> **Note:** Flash ターゲット設定は `plugins/flash/database/` に分離されている。

## 新しい MCU の追加

1. `mcu-database.json` に MCU 定義を追加
2. 新しいコアタイプの場合は `cortex-m.json` にも追加
3. PyOCD フラッシュ対応が必要なら `plugins/flash/database/flash-targets.json` にも追加

MCU エントリの例:

```json
"stm32f429zi": {
    "core": "cortex-m4f",
    "flash": "2M",
    "ram": "256K",
    "flash_origin": "0x08000000",
    "ram_origin": "0x20000000",
    "vendor": "st"
}
```

## プロジェクトローカルオーバーライド

プロジェクトに `mcu-local.json` を配置すると、`mcu-database.json` のエントリをオーバーライドできる。
カスタムメモリレイアウトやプロジェクト固有の設定に使用する。

