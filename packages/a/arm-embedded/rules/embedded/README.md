# ARM Embedded Build Rule

ARM 組込みビルドルールとデータベースモジュール。

## ディレクトリ構成

```
rules/embedded/
├── xmake.lua              # メインルール実装（embedded ルール）
├── database/
│   ├── cortex-m.json      # Cortex-M コア定義（アーキテクチャ、コンパイラフラグ、FPU）
│   ├── mcu-database.json  # MCU 固有設定（コア、Flash/RAM サイズ、メモリアドレス）
│   ├── build-options.json # ビルドオプション（最適化、デバッグ、C++ オプション）
│   ├── toolchain-configs.json  # ツールチェーン検出・設定
│   └── README.md          # データベース仕様
└── linker/                # リンカスクリプトテンプレート
```

## 関連ルール一覧

| ルール | ディレクトリ | 概要 |
|--------|-------------|------|
| `embedded` | `rules/embedded/` | メインビルドルール（MCU 設定、ツールチェーン、最適化） |
| `embedded.vscode` | `rules/vscode/` | VSCode launch.json / tasks.json 自動生成 |
| `embedded.compdb` | `rules/compdb/` | compile_commands.json 生成 |
| `embedded.test` | `rules/embedded.test/` | 組込みテスト自動化 |
| `firmware` | `rules/firmware/` | ファームウェアビルド（.bin/.hex 生成、サイズレポート） |
| `umios.firmware` | `rules/umios.firmware/` | UMI OS ファームウェア固有ルール |
| `host.test` | `rules/host.test/` | ホストテストルール |

> ルール名マッピング: ソースディレクトリ名 `vscode` → インストール時 `embedded.vscode`、`compdb` → `embedded.compdb`

## 使用方法

```lua
target("my-firmware")
    add_rules("embedded")
    set_values("embedded.mcu", "stm32f407vg")
    set_values("embedded.toolchain", "gcc")  -- or "llvm"
    set_values("embedded.optimize", "size")  -- size/speed/balanced/debug
    set_values("embedded.c_standard", "c11")
    set_values("embedded.cxx_standard", "c++23")
```

### 自動適用される C++ コンパイラフラグ

- `-fno-rtti`: RTTI 無効化
- `-fno-exceptions`: 例外処理無効化
- `-fno-threadsafe-statics`: スレッドセーフ静的初期化無効化

組込み C++ 開発の標準（コードサイズ削減、ランタイムオーバーヘッド排除）。

## データベースファイル（JSON 形式）

### cortex-m.json

Cortex-M コア定義:
- アーキテクチャ仕様（ARMv6-M, ARMv7-M, ARMv8-M 等）
- GCC / LLVM コンパイラフラグ
- FPU 設定
- ライブラリパス

### mcu-database.json

MCU 固有設定:
- コアタイプマッピング
- Flash / RAM サイズ
- メモリオリジンアドレス
- ベンダー情報

### build-options.json

ビルド設定オプション:
- 最適化レベル（size, speed, balanced, debug）
- デバッグオプション
- C++ オプション（RTTI, exceptions 等）
- ツールチェーン固有リンカオプション

### toolchain-configs.json

ツールチェーン管理:
- ツールチェーン検出パターン
- GCC / LLVM バイナリマッピング
- パッケージパスとバージョン検出

## MCU の追加

`database/mcu-database.json` に新しいエントリを追加:

```json
{
    "stm32f103c8": {
        "core": "cortex-m3",
        "flash": "64K",
        "ram": "20K",
        "flash_origin": "0x08000000",
        "ram_origin": "0x20000000",
        "vendor": "st"
    }
}
```

### mcu-local.json によるオーバーライド

プロジェクトルートに `mcu-local.json` を配置すると、`mcu-database.json` の定義をプロジェクト固有にオーバーライドできる:

```json
{
    "stm32f407vg": {
        "ram": "192K",
        "extra_memory": {
            "ccm": { "origin": "0x10000000", "size": "64K" }
        }
    }
}
```

## コアの追加

`database/cortex-m.json` に新しいエントリを追加:

```json
{
    "cortex-m55": {
        "arch": "armv8.1-m.main",
        "gcc": { "mcpu": "cortex-m55", "mfpu": "fpv5-sp-d16", "mfloat_abi": "hard" },
        "llvm": { "target": "armv8.1m.main-none-eabi", "mfpu": "fpv5-sp-d16", "mfloat_abi": "hard" },
        "features": { "thumb": true, "dsp": true, "mve": true, "trustzone": true, "fpu": "fpv5-sp-d16" },
        "lib": "armv8_1m_main_hard_fpv5_sp_d16/lib"
    }
}
```