# Coding Rules Package

C++ コーディングスタイルとテスト自動化のための xmake パッケージ。

## 概要

`coding-rules` パッケージは、C++ プロジェクトの自動コードフォーマット、静的解析、テスト自動化を提供する。

## 主な機能

- **コードフォーマット**: clang-format による自動フォーマット（`xmake format` / `xmake coding-format`）
- **静的解析**: clang-tidy による命名規則・コード品質チェック（`xmake lint`）
- **統合チェック**: フォーマット + lint + ビルドを一括実行（`xmake coding-check`）
- **ヘッダーコメント整列**: `@file`, `@brief` 等の順序を自動修正（`xmake format-headers`）
- **テスト自動化**: サニタイザ・カバレッジ対応のテストルール
- **Claude Code 統合**: Claude Code の hooks/rules/skills/MCP を自動セットアップ（`xmake setup-claude`）

## インストール

```lua
add_repositories("synthernet https://github.com/your-repo/xmake-repo.git")
add_requires("coding-rules")
```

## ルール

### coding.style

> **Note:** Phase 7 で `before_build` が削除され、実質 no-op。後方互換のために残されている。
> コードフォーマットは `xmake format` / `xmake coding-format` を使用すること。

```lua
target("my-app")
    add_rules("coding.style")
    add_files("src/*.cc")
```

`on_config` でプロジェクトルートの `.clang-format` / `.clang-tidy` のパスを設定するのみ。

### coding.style.ci

> **Note:** 同様に no-op。CI 環境では `xmake coding-check --ci` を使用すること。

```lua
target("my-app")
    add_rules("coding.style.ci")
    add_files("src/*.cc")
```

### coding.test

テストターゲットにサニタイザとビルドフラグを自動設定する:

```lua
target("my-test")
    add_rules("coding.test")
    set_values("testing.sanitizers", {"address", "undefined"})
    add_files("test/*.cc")
```

自動設定される内容:
- デバッグシンボル有効化
- `-Wall -Wextra -Wpedantic -Werror` フラグ追加
- `TEST_BUILD` プリプロセッサ定義
- サニタイザフラグ（ホストビルド時のみ）

サポートされるサニタイザ（ホストビルドのみ）:
- `address`: メモリエラー検出
- `undefined`: 未定義動作検出
- `thread`: データ競合検出
- `memory`: 未初期化メモリ検出

### coding.test.coverage

コードカバレッジ解析を有効化する。`coding.test` に依存:

```lua
target("my-test")
    add_rules("coding.test.coverage")
    add_files("test/*.cc")
```

- clang: `-fprofile-instr-generate -fcoverage-mapping` + `llvm-profdata`/`llvm-cov`
- gcc: `--coverage` + `gcov`

## xmake タスク（プラグイン）

### xmake format

clang-format を使用してソースコードをフォーマット:

```bash
xmake format                           # lib/ + examples/ をフォーマット
xmake format -t my-app                 # 特定ターゲットのみ
xmake format -i src/foo.cc,src/bar.cc  # 指定ファイルのみ
xmake format --dry-run                 # チェックのみ（変更なし）
```

スキャン対象: `lib/`, `examples/`（`/build/`, `/.xmake/`, `/.ref/`, `/third_party/`, `/_archive/` を除外）。

### xmake coding-format

`format` と同様だが、共有 `file_collector` スクリプトを使用してプロジェクトルート全体をスキャン:

```bash
xmake coding-format                    # プロジェクト全体をフォーマット
xmake coding-format --dry-run          # チェックのみ
```

除外: `/build/`, `/.xmake/` のみ（より広い範囲をスキャン）。

### xmake lint

compile_commands.json を使用して clang-tidy を実行:

```bash
xmake lint                             # 全ソースを解析
xmake lint -t my-app                   # 特定ターゲットのパターンでフィルタ
xmake lint --changed                   # git 変更ファイルのみ
xmake lint --fix                       # 自動修正
xmake lint -c "readability-*"          # チェック項目を指定
xmake lint --json                      # JSON 出力（MCP 統合用）
```

compdb 検索パス: `build/compdb/compile_commands.json` → `compile_commands.json`

### xmake coding-check

フォーマット + lint + ビルドを一括実行:

```bash
xmake coding-check                     # coding-format → lint
xmake coding-check --full              # coding-format → lint → build
xmake coding-check --ci                # CI モード（dry-run format + lint + build）
xmake coding-check --changed           # git 変更ファイルのみ lint
```

### xmake format-headers

ファイルヘッダーコメントの順序を API_COMMENT_RULE §2.1 に合わせて整列:

```bash
xmake format-headers                   # ヘッダーコメント順序を修正
xmake format-headers --dry-run         # 変更内容を表示のみ
```

`.header-order.lua` で設定可能（scan_dirs, extensions, exclude 等）。デフォルト拡張子: `.hh`, `.ipp`

### xmake setup-claude

Claude Code の hooks, rules, skills, agents, MCP 設定を `.claude/` にデプロイ:

```bash
xmake setup-claude                     # 初回デプロイ
xmake setup-claude --force             # 全ファイル強制上書き
```

2段階デプロイ:
1. Stage 1 (パッケージ on_load): packages → `~/.xmake/`（自動）
2. Stage 2 (このプラグイン): `~/.xmake/` → `.claude/`（手動、1回）

## 設定ファイル

パッケージから以下の設定ファイルテンプレートが提供される（`rules/coding/configs/` に格納）:

- `.clang-format`: コードフォーマットルール（LLVM ベース、4 スペースインデント、120 文字行制限）
- `.clang-tidy`: 静的解析・命名規則設定
- `.clangd`: Language Server 設定

## コーディング規約

### 命名規則

| 要素 | 規則 | 例 |
|------|------|-----|
| クラス / 構造体 / 列挙型 | `CamelCase` | `AudioProcessor`, `ConnectionState` |
| 関数 / メソッド | `snake_case` | `process_audio()`, `is_connected()` |
| 変数 / パラメータ | `snake_case` | `buffer_size`, `sample_rate` |
| メンバー変数 | `snake_case`（プレフィックス/サフィックスなし） | `device_info`（`m_` や `_` サフィックスは禁止） |
| constexpr 変数 | `snake_case` | `constexpr int max_channels = 16;` |
| enum 値 | `UPPER_CASE` | `CONNECTING`, `MIDI_1_0` |
| 名前空間 | `snake_case` | `audio_processing` |

> **重要:** メンバー変数にプレフィックス (`m_`) やサフィックス (`_`) を使用しない。
> 必要な場合は `this->` で曖昧さを解消する。

### const vs constexpr

- **constexpr 変数**: `snake_case` — `constexpr` only, never `inline constexpr`（C++17 以降は暗黙的に inline）
- **グローバル const 定数**: `UPPER_CASE` — `const size_t MAX_BUFFER_SIZE = 4096;`
- **ローカル const**: `snake_case` — `const auto timeout = std::chrono::seconds(5);`

## 必要なツール

- clang-format（フォーマット用）
- clang-tidy（静的解析用）
- C++23 対応コンパイラ

## ディレクトリ構成

```
packages/c/coding-rules/
├── xmake.lua                    # パッケージ定義 (on_load でルール・プラグインをインストール)
├── README.md                    # このファイル
├── rules/
│   ├── coding/
│   │   ├── xmake.lua            # coding.style / coding.style.ci ルール（no-op、後方互換用）
│   │   └── configs/             # .clang-format, .clang-tidy, .clangd テンプレート
│   └── testing/
│       └── xmake.lua            # coding.test / coding.test.coverage ルール
├── plugins/
│   ├── format/                  # xmake format（lib/ + examples/ スキャン）
│   ├── coding-format/           # xmake coding-format（プロジェクト全体スキャン）
│   ├── lint/                    # xmake lint（clang-tidy）
│   ├── coding-check/            # xmake coding-check（format + lint + build）
│   ├── format-headers/          # xmake format-headers（ヘッダーコメント順序）
│   └── setup-claude/            # xmake setup-claude（Claude Code 統合）
├── scripts/
│   ├── file_collector.lua       # 共有ファイルスキャンモジュール
│   └── json_pretty.lua          # JSON 整形ユーティリティ
├── claude/                      # Claude Code 統合ファイル (hooks, rules, mcp)
├── docs/
│   ├── style_guide.md           # スタイルガイド詳細
│   └── check_and_tests.md       # チェック・テストガイド
└── examples/
    └── good_style.cc            # スタイル適用例
```

## ライセンス

MIT License
