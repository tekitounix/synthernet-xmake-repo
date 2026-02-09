# PHC — Package Health Check

xmake プラグインとして動作するパッケージ管理ツール。
synthernet リポジトリ内の外部パッケージ（clang-arm, gcc-arm, renode 等）のダウンロードリンク検証、
上流バージョン検出、xmake.lua 自動生成、バージョン自動更新を行う。

## アーキテクチャ

```
packages.lua (Single Source of Truth)
    │
    ├─ check-links    → リンク有効性検証
    ├─ check-updates  → 上流新バージョン検出
    ├─ validate       → registry ↔ xmake.lua 整合性検証
    ├─ generate       → xmake.lua 完全生成
    └─ update-package → DL + SHA256 + packages.lua 更新 + xmake.lua 再生成
```

`packages.lua` がすべてのパッケージデータ（バージョン、URL テンプレート、SHA256 ハッシュ、メタデータ、
インストール方式）を保持する唯一の情報源。各パッケージの `xmake.lua` は `generate` コマンドで
100% 生成される。手動編集は不要。

## インストール

```bash
# xmake require 経由（on_load で自動コピー）
xmake require phc

# 手動インストール
mkdir -p ~/.xmake/plugins/phc
cp -r plugins/phc/* ~/.xmake/plugins/phc/
cp -r registry ~/.xmake/plugins/phc/
```

## 使い方

```bash
# リンク検証
xmake phc check-links                          # 全パッケージ
xmake phc check-links -p clang-arm             # 特定パッケージ

# 上流バージョン検出
xmake phc check-updates -o report.json         # JSON レポート出力

# registry ↔ xmake.lua 整合性検証
xmake phc validate

# xmake.lua 生成
xmake phc generate                             # 全パッケージ生成
xmake phc generate -p clang-arm -n             # dry-run（差分表示のみ）

# バージョン自動更新（DL + SHA256 + packages.lua 更新 + xmake.lua 再生成）
xmake phc update-package -p gcc-arm            # 新バージョン自動検出
xmake phc update-package -p renode --target-version=1.16.1  # 指定バージョン
xmake phc update-package -p gcc-arm --force    # 既存バージョンでも再ダウンロード
```

### オプション一覧

| オプション | 短縮 | 説明 |
|-----------|------|------|
| `--package <name>` | `-p` | 対象パッケージを指定 |
| `--output <file>` | `-o` | JSON レポートをファイル出力 |
| `--registry <path>` | `-r` | packages.lua のパスを指定 |
| `--packages-dir <dir>` | — | packages/ ディレクトリのパス (validate/generate 用) |
| `--dry-run` | `-n` | 差分表示のみ、ファイル変更なし (generate 用) |
| `--target-version=<v>` | — | 更新対象バージョンを指定 (update-package 用) |
| `--force` | — | 既存バージョンでも再ダウンロード (update-package 用) |

> **Note:** `--target-version` は `=` 区切りが必要 (`--target-version=1.16.1`)。
> スペース区切り (`--target-version 1.16.1`) は xmake のオプションパーサーの制約で動作しない。

## packages.lua スキーマ (v2)

```lua
{
    _meta = {
        schema_version = 2,
        description = "synthernet package registry — single source of truth"
    },
    ["package-name"] = {
        -- ■ ソース情報
        type = "github-release",        -- or "http-direct"
        repo = "owner/repo",            -- github-release の場合
        base_url = "https://...",        -- http-direct の場合
        tag_pattern = "v%(version)",     -- タグテンプレート
        fallback_tag_pattern = "...",    -- フォールバックタグ (省略可)
        update_check = {                 -- type と異なるソースで更新検出 (省略可)
            type = "github-release",
            repo = "owner/other-repo"
        },
        source_overrides = {             -- バージョン別ソース上書き (省略可)
            {
                version_ge = "2.0.0",    -- このバージョン以上に適用 (セマンティック比較)
                repo = "new-owner/repo", -- 上書き対象フィールド (省略時はデフォルト値を継承)
                tag_pattern = "...",
                fallback_tag_pattern = false, -- false で明示的に無効化
                assets = { ... },
                discover_from = true,    -- バージョン検出にこのソースを使用
            },
        },

        -- ■ バージョン・アセット
        versions = {"1.2.0", "1.1.0"},  -- 先頭が最新
        version_map = {                  -- セマンティック → リリース名変換 (省略可)
            ["1.2.0"] = "1.2.rel1"
        },
        assets = {                       -- プラットフォームID → ファイル名テンプレート
            ["linux-x86_64"]  = "tool-%(version)-linux-x64.tar.xz",
            ["macos-arm64"]   = "tool-%(version)-macos.dmg",
            -- ...
        },
        exclusions = {                   -- 特定バージョン/プラットフォームの除外 (省略可)
            ["1.2.0"] = {"macos-x86_64"}
        },

        -- ■ メタデータ (xmake.lua の set_kind/set_homepage/set_description に使用)
        metadata = {
            kind = "toolchain",          -- "toolchain" or "binary"
            homepage = "https://...",
            description = "..."
        },

        -- ■ インストール
        install = "toolchain-archive",   -- テンプレート名
        install_config = {               -- テンプレート固有の設定
            bin_verify = {"gcc --version"},
            toolchain_def = "toolchains/xmake.lua",
            -- ... テンプレートにより異なる
        },

        -- ■ ハッシュ
        hashes = {
            ["1.2.0"] = {
                ["linux-x86_64"] = "sha256hash...",
                -- ...
            }
        }
    }
}
```

### プラットフォーム ID

| ID | xmake 条件 |
|----|-----------|
| `linux-x86_64` | `is_host("linux")` (デフォルト) |
| `linux-aarch64` | `is_host("linux") and os.arch():find("arm64")` |
| `windows-x86_64` | `is_host("windows")` (デフォルト) |
| `windows-x86` | `is_host("windows") and os.arch() == "x86"` |
| `macos-universal` | `is_host("macosx")` |
| `macos-arm64` | `is_host("macosx")` |
| `macos-x86_64` | `is_host("macosx") and os.arch() ~= "arm64"` |
| `windows-portable` | `is_host("windows")` |

### インストールテンプレート

| テンプレート名 | 対象 | 説明 |
|--------------|------|------|
| `toolchain-archive` | clang-arm, gcc-arm | アーカイブ展開 + bin/検証 + ツールチェーン定義コピー |
| `binary-app` | renode | DMG/tar/zip 展開 + ラッパースクリプト生成 + on_fetch |

テンプレートは `modules/install_<name>.lua` に実装。`generate()` 関数が
on_install/on_load/on_test 等のコードブロックを文字列の配列として返す。

## ファイル構成

```
packages/p/phc/
├── xmake.lua                       # メタパッケージ定義 (on_load でプラグインをインストール)
├── README.md                       # このファイル
├── registry/
│   └── packages.lua                # Single Source of Truth (スキーマ v2)
└── plugins/phc/
    ├── xmake.lua                   # CLI エントリポイント (task 定義)
    └── modules/
        ├── registry.lua            # packages.lua の読み込み・スキーマ検証
        ├── checker.lua             # check-links / check-updates ロジック
        ├── validator.lua           # registry ↔ xmake.lua 整合性検証
        ├── reporter.lua            # stdout 色付き出力 + JSON 出力
        ├── generator.lua           # xmake.lua 生成エンジン
        ├── updater.lua             # update-package ロジック (DL + SHA256)
        ├── provider.lua            # Provider ファクトリ + ベースユーティリティ
        ├── provider_github.lua     # GitHub Releases Provider
        ├── provider_http.lua       # HTTP Direct Provider
        ├── install_toolchain_archive.lua  # toolchain-archive テンプレート
        └── install_binary_app.lua  # binary-app テンプレート
```

### モジュール詳細

| モジュール | 責務 |
|-----------|------|
| **registry** | `io.load()` で packages.lua を読み込み、スキーマバージョン検証。closure ベースの registry オブジェクトを返す |
| **checker** | Provider を生成して `resolve_urls()` / `check_link()` でリンク検証、`discover_versions()` で更新検出 |
| **validator** | xmake.lua を読み込み、`add_versions()` のバージョンと packages.lua のバージョンを突き合わせ。URL ドメインの整合性も検証 |
| **reporter** | 色付き stdout 出力 (`cprint`) と JSON ファイル出力。link/update/validation の3種のレポート形式 |
| **generator** | packages.lua からプラットフォーム条件分岐、URL テンプレート、バージョン/ハッシュ、インストールテンプレートを組み合わせて xmake.lua を完全生成 |
| **updater** | 新バージョン検出 → 各プラットフォームのアセットダウンロード → SHA256 計算 → packages.lua 更新 → xmake.lua 再生成 |
| **provider** | Provider パターンのファクトリ。`modules/` 内の `provider_*.lua` を auto-discover で動的登録。closure ベース |
| **provider_github** | GitHub Releases API (`/repos/:owner/:repo/releases`) から最新タグを取得。GITHUB_TOKEN 対応 |
| **provider_http** | HTTP HEAD リクエストでリンク有効性を検証。バージョン検出は update_check フィールドで GitHub に委譲可能 |
| **install_toolchain_archive** | clang-arm, gcc-arm 用テンプレート。macOS DMG / Linux tar / Windows zip に対応。on_load でツールチェーン定義コピー |
| **install_binary_app** | renode 用テンプレート。DMG マウント + アプリコピー、ラッパースクリプト生成、on_fetch オーバーライド |

## CI ワークフロー

`.github/workflows/check-packages.yml` で自動実行:

```
validate → generate-check  (xmake.lua が最新か dry-run で検証)
         → check-links     (ダウンロードリンク検証)
         → check-updates   (上流バージョン検出)
                ├→ auto-update  (スケジュール実行時: 自動更新 → PR 作成)
                └→ notify       (手動実行時: Issue 作成/更新)
```

| トリガー | 動作 |
|---------|------|
| 毎週月曜 09:00 UTC (schedule) | 全チェック + auto-update (PR 自動作成) |
| push (PHC/パッケージ変更時) | validate + generate-check + link/update チェック |
| workflow_dispatch | 手動実行。`auto_update: true` で自動更新有効化 |

## 開発ガイド

### 新パッケージを追加する手順

1. `registry/packages.lua` にエントリ追加（スキーマ v2 準拠）
2. 適切な `install` テンプレートを指定（既存 or 新規作成）
3. `xmake phc generate -p <name>` で xmake.lua 生成
4. `xmake phc validate` で整合性確認
5. `xmake phc check-links -p <name>` でリンク検証

### 新しい Provider を追加する

`modules/provider_<type>.lua` を作成するだけで自動認識される:

```lua
-- modules/provider_custom.lua
local base_mod = import("provider")

local function create(pkg_name, config)
    local self = base_mod.new_base(pkg_name, config)
    -- resolve_urls(), check_link(), discover_versions() を実装
    return self
end

base_mod.register("custom", create)
```

### 新しいインストールテンプレートを追加する

`modules/install_<name>.lua` を作成:

```lua
-- modules/install_my_template.lua
function generate(pkg_name, config)
    local lines = {}
    -- on_install, on_load, on_test 等のコードを文字列で構築
    return lines
end
```

`packages.lua` で `install = "my-template"` と指定すると
generator が `import("install_my_template")` で自動ロードする。

### xmake サンドボックスの制約

PHC モジュールは xmake サンドボックス内で動作するため、以下の制約がある:

| 制約 | 回避策 |
|------|--------|
| `setmetatable()` 不可 | closure ベースのオブジェクトパターン |
| `select()` 不可 | 明示的な引数 (`a1, a2, a3, a4`) |
| `pcall()` 不可 | `try { function() ... end }` |
| `error()` 不可 | `raise()` |
| `import()` はモジュールスコープの非ローカル関数のみエクスポート | `local` を付けないで関数定義 |
