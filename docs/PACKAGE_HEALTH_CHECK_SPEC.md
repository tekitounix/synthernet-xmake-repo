# Package Health Check (PHC) — 仕様設計書

> **Version:** 3.1 (実装準拠版)
> **Status:** Implemented
> **Language:** Lua (xmake plugin)
> **Dependencies:** xmake のみ（外部依存ゼロ）
> **Scope:** synthernet xmake-repo パッケージの URL/バージョン監視

---

## 1. 目的と設計原則

### 1.1 目的

外部パッケージのダウンロード URL とバージョンを CI で自動監視し、
リンク切れや新バージョン公開を検知して通知する。

| 検知項目 | 対応 |
|---------|------|
| **リンク切れ** | Issue 自動作成 → 手動修正 |
| **新バージョン公開** | Issue 自動作成 → 手動追加 |
| **データ整合性** | CI fail → 手動修正 |

**基本方針: 検知は自動、修正は手動。**

### 1.2 設計原則

| 原則 | 説明 |
|------|------|
| **外部依存ゼロ** | xmake の Lua ランタイムのみで動作。Python/Node 不要 |
| **xmake ネイティブ** | `xmake phc` で呼び出し。既存の `release.lua`, `arm-embedded` plugin と同じ配布パターン |
| **Provider パターン** | パッケージソース種別を Provider モジュールで抽象化。新ソース追加≒モジュール1ファイルの追加 |
| **データ駆動** | 全設定は Lua テーブル (`packages.lua`) に集約。コード変更なしで新パッケージ追加可能 |
| **スキーマバージョニング** | データにバージョンを付与し、後方互換な進化を保証 |
| **ゼロ特殊分岐** | パッケージ固有ロジックはデータで表現 (`version_map`, `exclusions`, `tag_transform`) |
| **ミラー対応準備** | v1 ではデータ構造に `sources[]` を予約。v2 でフォールバック / ミラー切り替えを実装 |

### 1.3 言語選定の根拠

| 候補 | 判定 | 理由 |
|------|:---:|------|
| **Lua (xmake plugin)** | **◎ 採用** | 依存ゼロ、xmake.lua 直接パース可、既存 plugin 配布パターン実績あり |
| Python | △ | python3 + pip 依存、TOML ↔ xmake.lua 二重管理 |
| TypeScript | △ | Node.js 依存、xmake エコシステムと乖離 |

**決め手:**
- `release.lua` (450行)、`arm-embedded` plugin 群が同じパターンで安定稼働
- `json`, `hash.sha256` 等の必要な機能が xmake 内蔵
- `io.load()` で Lua テーブルデータを即読み込み — パーサー不要
- `coding-rules` / `arm-embedded` と同じ `~/.xmake/plugins/` 配布で解決済み

### 1.4 xmake サンドボックス制約

xmake プラグインは Lua サンドボックス内で動作し、以下の標準 Lua 機能が**利用不可**:

| 利用不可 | 代替手段 | 備考 |
|---------|---------|------|
| `setmetatable()` | Closure ベース OOP | テーブル + 関数クロージャで代替 |
| `pcall()` | `try { function() ... end, catch { function(err) ... end } }` | xmake 独自構文 |
| `error()` | `raise()` | `raise("msg %s", arg)` でフォーマット文字列対応 |
| `dofile()` / `loadfile()` | `io.load()` | xmake 独自シリアライズ形式（`return` 不可、コメント不可） |
| `loadstring()` / `load()` | 不可 | 代替なし |
| `set_description()` 単独 | `set_menu { description = "..." }` 内に記述 | task スコープでのみ有効 |
| `import()` の `return` | 非ローカル関数をモジュールスコープに定義 | `return { func = func }` は**無視される** |

**`import()` の動作:**
- モジュールスコープの**非ローカル関数**のみがエクスポートされる
- `local function foo()` はエクスポート**されない**
- `function foo()` はエクスポートされる
- `return` 文の値は完全に無視される
- 同ディレクトリのモジュールはパス省略可: `import("provider")` = `import("modules.provider")` (同 modules/ 内)

**`io.load()` のフォーマット:**
```lua
-- ✗ 以下は io.load() で読めない:
return { key = "value" }  -- return 不可
-- コメントも不可

-- ✓ 正しい形式（io.save() 出力互換）:
{
    key = "value",
    nested = {1, 2, 3}
}
```

**option parsing:**
- `set_menu.options` の配列で、positional `"v"` は**必ず最後**に配置
- `"kv"` オプションを先、`"v"` を後にしないと named option が正しくパースされない
- CLI 使用例: `xmake phc -p renode check-links` (kv → positional の順)

---

## 2. 対象パッケージの分類

### 2.1 現行対象（v1 スコープ）

| パッケージ | Provider | ソース | 登録バージョン |
|-----------|----------|--------|---------------|
| `clang-arm` | `github-release` | `ARM-software/LLVM-embedded-toolchain-for-Arm` | 19.1.5, 19.1.1, 18.1.3 |
| `gcc-arm` | `http-direct` | `armkeil.blob.core.windows.net` | 14.3.1, 14.2.1 |
| `renode` | `github-release` | `renode/renode` | 1.16.0 |

### 2.2 対象外

| パッケージ | 理由 |
|-----------|------|
| `arm-embedded`, `coding-rules` | メタパッケージ（DL 無し） |
| `python3`, `pyocd` | pip/system ラッパー |
| `umiport` | ローカル専用 |
| `umibench`, `umimmio`, `umirtm`, `umitest` | 既存 `release.yml` が管理 |

### 2.3 将来追加が想定される Provider

| Provider | ユースケース |
|---------|-------------|
| `github-release` | GitHub Releases からアセット取得（大多数の OSS ツール） |
| `http-direct` | CDN / 公式サイトの直リンク（ARM CDN, SEGGER 等） |
| `gitlab-release` | GitLab Releases |
| `pypi` | PyPI パッケージ |
| `github-tag` | GitHub Tag（Release なし） |
| `s3` | AWS S3 / R2 バケット |

---

## 3. アーキテクチャ

### 3.1 ディレクトリ構造

```
xmake-repo/synthernet/packages/p/phc/
├── xmake.lua                          ← パッケージ定義 (on_load で plugin インストール)
├── plugins/
│   └── phc/
│       ├── xmake.lua                  ← task("phc") エントリポイント
│       └── modules/
│           ├── registry.lua           ← レジストリ読み込み + スキーマ検証
│           ├── provider.lua           ← Provider 基底 + ファクトリ (closure ベース)
│           ├── provider_github.lua    ← GitHub Releases Provider
│           ├── provider_http.lua      ← HTTP Direct Provider
│           ├── checker.lua            ← リンク切れ + バージョン検知
│           ├── validator.lua          ← registry ↔ xmake.lua 整合性
│           ├── generator.lua          ← xmake.lua 生成エンジン
│           ├── updater.lua            ← update-package ロジック (DL + SHA256)
│           ├── reporter.lua           ← 出力 (JSON, stdout)
│           ├── install_toolchain_archive.lua  ← toolchain-archive テンプレート
│           └── install_binary_app.lua ← binary-app テンプレート
└── registry/
    └── packages.lua                   ← データ定義 (Single Source of Truth, スキーマ v2)
```

> **Note:** xmake `import()` の同ディレクトリ解決により、`modules/` 内は
> フラット構造で配置。`providers/` サブディレクトリは使わない（cross-directory import が不安定なため）。

### 3.2 レイヤー構成

```
┌──────────────────────────────────────────────────┐
│          CLI Layer: task("phc")                    │
│  xmake phc [-p pkg] [-o file] <command>            │
└──────────────┬──────────────────┬─────────────────┘
               │                  │
               ▼                  ▼
┌──────────────────────┐   ┌───────────────────┐
│  checker.lua          │   │  validator.lua     │
│  check_links()        │   │  validate()        │
│  check_updates()      │   │                    │
└──────────┬───────────┘   └────────┬──────────┘
           │                        │
           ▼                        │
┌──────────────────────┐            │
│  provider.lua         │            │
│  (ファクトリ + base)   │            │
│  provider_github.lua  │            │
│  provider_http.lua    │            │
└──────────┬───────────┘            │
           │                        │
           ▼                        ▼
┌──────────────────────────────────────────────┐
│  registry.lua                                 │
│  packages.lua ← Single Source of Truth (v2)   │
└──────────────┬───────────────────────────────┘
               │
        ┌──────┴──────┐
        ▼             ▼
┌──────────────┐ ┌──────────────┐
│ generator.lua │ │ updater.lua  │
│ xmake.lua生成  │ │ DL+SHA256    │
└──────┬───────┘ └──────┬───────┘
       │                │
       ▼                ▼
┌──────────────────────────────┐
│  install_*.lua                │
│  (toolchain_archive,          │
│   binary_app)                 │
└──────────────────────────────┘
               │
               ▼
┌──────────────────────┐
│  reporter.lua         │
│  json / stdout        │
└──────────────────────┘
```

### 3.3 プラグイン配布（既存パターン踏襲）

```
xmake require phc  (or on_load triggered)
    │
    ▼  on_load() → sync_tree()
~/.xmake/plugins/phc/
├── xmake.lua           ← task("phc")
├── modules/            ← 全モジュール
└── registry/           ← packages.lua
    │
    ▼
xmake phc check-links   ← 即使用可能
```

`arm-embedded` パッケージの `on_load()` が `~/.xmake/plugins/` へコピーする
既存パターンをそのまま踏襲する。

---

## 4. データ定義: `registry/packages.lua`

### 4.1 完全な定義

> **重要:** `io.load()` 形式。`return` 不可、コメント不可。純粋な Lua テーブルリテラル。

```lua
{
    _meta = {
        schema_version = 2,
        description = "synthernet package registry for health check"
    },
    ["clang-arm"] = {
        type = "github-release",
        repo = "ARM-software/LLVM-embedded-toolchain-for-Arm",
        tag_pattern = "release-%(version)",
        fallback_tag_pattern = "preview-%(version)",
        versions = {"19.1.5", "19.1.1", "18.1.3"},
        assets = {
            ["linux-aarch64"]   = "LLVM-ET-Arm-%(version)-Linux-AArch64.tar.xz",
            ["linux-x86_64"]    = "LLVM-ET-Arm-%(version)-Linux-x86_64.tar.xz",
            ["windows-x86_64"]  = "LLVM-ET-Arm-%(version)-Windows-x86_64.zip",
            ["macos-universal"]  = "LLVM-ET-Arm-%(version)-Darwin-universal.dmg"
        }
    },
    ["gcc-arm"] = {
        type = "http-direct",
        base_url = "https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/%(mapped_version)/binrel",
        update_check = {
            type = "github-release",
            repo = "ARM-software/arm-gnu-toolchain-releases"
        },
        versions = {"14.3.1", "14.2.1"},
        version_map = {
            ["14.2.1"] = "14.2.rel1",
            ["14.3.1"] = "14.3.rel1"
        },
        assets = {
            ["linux-aarch64"]  = "arm-gnu-toolchain-%(mapped_version)-aarch64-arm-none-eabi.tar.xz",
            ["linux-x86_64"]   = "arm-gnu-toolchain-%(mapped_version)-x86_64-arm-none-eabi.tar.xz",
            ["windows-x86"]    = "arm-gnu-toolchain-%(mapped_version)-mingw-w64-i686-arm-none-eabi.zip",
            ["windows-x86_64"] = "arm-gnu-toolchain-%(mapped_version)-mingw-w64-x86_64-arm-none-eabi.zip",
            ["macos-x86_64"]   = "arm-gnu-toolchain-%(mapped_version)-darwin-x86_64-arm-none-eabi.tar.xz",
            ["macos-arm64"]    = "arm-gnu-toolchain-%(mapped_version)-darwin-arm64-arm-none-eabi.tar.xz"
        },
        exclusions = {
            ["14.3.1"] = {"macos-x86_64"}
        }
    },
    ["renode"] = {
        type = "github-release",
        repo = "renode/renode",
        tag_pattern = "v%(version)",
        versions = {"1.16.0"},
        assets = {
            ["linux-x86_64"]      = "renode-%(version).linux-portable-dotnet.tar.gz",
            ["linux-aarch64"]     = "renode-%(version).linux-arm64-portable-dotnet.tar.gz",
            ["macos-arm64"]       = "renode-%(version)-dotnet.osx-arm64-portable.dmg",
            ["windows-portable"]  = "renode-%(version).windows-portable-dotnet.zip"
        }
    }
}
```

### 4.2 テンプレート変数

| 変数 | 展開元 | 使用箇所 |
|------|--------|---------|
| `%(version)` | `versions[]` の各要素 | `tag_pattern`, `base_url`, `assets` |
| `%(mapped_version)` | `version_map[version]`（未定義時は `version` にフォールバック） | `base_url`, `assets` |

テンプレート展開の実装:

```lua
function self.expand(template, version)
    local vars = {
        version        = version,
        mapped_version = self.mapped_version(version),
    }
    -- [%w_]+ で underscore を含むキー (mapped_version) にマッチ
    return template:gsub("%%%(([%w_]+)%)", function(key)
        return vars[key] or ("<" .. key .. ">")
    end)
end
```

> **注意:** `%w+` ではアンダースコアにマッチしない。`[%w_]+` を使用すること。

### 4.3 スキーマバージョン運用

| 変更種別 | schema_version | 例 |
|---------|:---:|-----|
| optional フィールド追加 | 変更なし | `include_prerelease` 追加 |
| 新 Provider 追加 | 変更なし | `pypi` Provider |
| フィールド名変更 / 削除 | +1 | `tag_pattern` → `tag_template` |
| セクション構造変更 | +1 | `assets` テーブルの形式変更 |

---

## 5. Provider インタフェース

### 5.1 基底 + ファクトリ: `provider.lua`

Closure ベース OOP（xmake sandbox では `setmetatable` 不可のため）。
`import()` でエクスポートされるのは非ローカル関数のみ。

```lua
-- plugins/phc/modules/provider.lua

-------------------------------------------------------------------
-- ファクトリレジストリ (モジュールスコープ)
-------------------------------------------------------------------
REGISTRY = {}

function register(type_name, constructor)
    REGISTRY[type_name] = constructor
end

function create(pkg_name, config)
    local provider_type = config.type
    local ctor = REGISTRY[provider_type]
    if not ctor then
        local known = {}
        for k, _ in pairs(REGISTRY) do table.insert(known, k) end
        raise("unknown provider type '%s' for package '%s'. known: %s",
            provider_type, pkg_name, table.concat(known, ", "))
    end
    return ctor(pkg_name, config)
end

-------------------------------------------------------------------
-- ベースユーティリティ (closure で返す)
-------------------------------------------------------------------
function new_base(pkg_name, config)
    local self = {
        pkg_name    = pkg_name,
        config      = config,
        versions    = config.versions or {},
        assets      = config.assets or {},
        version_map = config.version_map or {},
        exclusions  = config.exclusions or {},
    }

    function self.mapped_version(version)
        return self.version_map[version] or version
    end

    function self.is_excluded(version, platform)
        local excl = self.exclusions[version]
        if not excl then return false end
        for _, p in ipairs(excl) do
            if p == platform then return true end
        end
        return false
    end

    function self.expand(template, version)
        local vars = {
            version        = version,
            mapped_version = self.mapped_version(version),
        }
        return template:gsub("%%%(([%w_]+)%)", function(key)
            return vars[key] or ("<" .. key .. ">")
        end)
    end

    return self
end
```

### 5.2 GitHub Release Provider: `provider_github.lua`

```lua
-- plugins/phc/modules/provider_github.lua

local provider_mod = import("provider")

--- GitHub API GET via curl
function api_get(url)
    local argv = {"-sS", "-w", "\n%{http_code}",
                  "-H", "Accept: application/vnd.github+json"}
    local token = os.getenv("GITHUB_TOKEN")
    if token then
        table.insert(argv, "-H")
        table.insert(argv, "Authorization: Bearer " .. token)
    end
    table.insert(argv, url)

    local outdata = nil
    local exec_ok = true
    try {
        function()
            outdata = os.iorunv("curl", argv)
        end,
        catch {
            function(err)
                exec_ok = false
            end
        }
    }
    if not exec_ok or not outdata then
        return false, "curl execution failed", nil
    end

    local lines = {}
    for line in outdata:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    if #lines == 0 then
        return false, "empty response", nil
    end

    local http_status = tonumber(lines[#lines]) or 0
    table.remove(lines, #lines)
    local body = table.concat(lines, "\n")

    if http_status >= 200 and http_status < 400 then
        return true, body, http_status
    else
        return false, body, http_status
    end
end

function new(pkg_name, config)
    local self = provider_mod.new_base(pkg_name, config)

    self.repo                 = config.repo
    self.tag_pattern          = config.tag_pattern
    self.fallback_tag_pattern = config.fallback_tag_pattern
    self.include_prerelease   = config.include_prerelease or false

    local function format_tag(version)
        return self.expand(self.tag_pattern, version)
    end

    function self.resolve_urls()
        local results = {}
        for _, version in ipairs(self.versions) do
            local tag = format_tag(version)
            for platform, template in pairs(self.assets) do
                if not self.is_excluded(version, platform) then
                    local asset_name = self.expand(template, version)
                    local url = ("https://github.com/%s/releases/download/%s/%s"):format(
                        self.repo, tag, asset_name)
                    table.insert(results, {
                        package  = self.pkg_name,
                        version  = version,
                        platform = platform,
                        url      = url,
                    })
                end
            end
        end
        return results
    end

    function self.check_link(asset)
        local tag = format_tag(asset.version)
        local expected = self.expand(self.assets[asset.platform], asset.version)
        local api_url = ("https://api.github.com/repos/%s/releases/tags/%s"):format(self.repo, tag)

        local ok, body, status = api_get(api_url)

        if not ok and self.fallback_tag_pattern then
            local fallback_tag = self.expand(self.fallback_tag_pattern, asset.version)
            local fallback_url = ("https://api.github.com/repos/%s/releases/tags/%s"):format(
                self.repo, fallback_tag)
            ok, body, status = api_get(fallback_url)
        end

        if not ok then
            return {asset = asset, status = "fail", http_status = status, error = body}
        end

        import("core.base.json")
        local release = nil
        local json_ok = true
        try {
            function()
                release = json.decode(body)
            end,
            catch {
                function(err)
                    json_ok = false
                end
            }
        }
        if not json_ok or not release then
            return {asset = asset, status = "fail", http_status = status, error = "JSON parse failed"}
        end

        for _, a in ipairs(release.assets or {}) do
            if a.name == expected then
                return {asset = asset, status = "ok", http_status = 200, error = nil}
            end
        end

        return {asset = asset, status = "fail", http_status = 200,
                error = ("asset '%s' not in release"):format(expected)}
    end

    function self.discover_versions()
        local api_url = ("https://api.github.com/repos/%s/releases?per_page=50"):format(self.repo)
        local ok, body, status = api_get(api_url)
        if not ok then return {} end

        import("core.base.json")
        local releases = nil
        local json_ok = true
        try {
            function()
                releases = json.decode(body)
            end,
            catch {
                function(err)
                    json_ok = false
                end
            }
        }
        if not json_ok or type(releases) ~= "table" then return {} end

        -- tag_pattern → 逆変換 Lua パターン
        -- "release-%(version)" → "^release%-(.+)$"
        local escaped = self.tag_pattern:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
        local lua_pattern = "^" .. escaped:gsub("%%%%%%%%%(version%)", "(.+)") .. "$"

        local known = {}
        for _, v in ipairs(self.versions) do known[v] = true end

        local results = {}
        for _, release in ipairs(releases) do
            if not release.draft and (self.include_prerelease or not release.prerelease) then
                local tag = release.tag_name
                local version = tag:match(lua_pattern)
                if version then
                    table.insert(results, {
                        version = version,
                        tag     = tag,
                        is_new  = not known[version],
                    })
                end
            end
        end
        return results
    end

    return self
end

-- ファクトリに登録
provider_mod.register("github-release", new)
```

### 5.3 HTTP Direct Provider: `provider_http.lua`

```lua
-- plugins/phc/modules/provider_http.lua

local provider_mod = import("provider")

--- curl で HTTP ステータスコードのみ取得
function curl_status(...)
    local argv = {"-sS", "-o", "/dev/null", "-w", "%{http_code}", "-L"}
    for _, arg in ipairs({...}) do
        table.insert(argv, arg)
    end

    local outdata = nil
    local exec_ok = true
    try {
        function()
            outdata = os.iorunv("curl", argv)
        end,
        catch {
            function(err)
                exec_ok = false
            end
        }
    }
    if not exec_ok or not outdata then
        return 0
    end
    return tonumber(outdata:match("(%d+)")) or 0
end

function new(pkg_name, config)
    local self = provider_mod.new_base(pkg_name, config)

    self.base_url     = config.base_url
    self.update_check = config.update_check

    function self.resolve_urls()
        local results = {}
        for _, version in ipairs(self.versions) do
            local base = self.expand(self.base_url, version)
            for platform, template in pairs(self.assets) do
                if not self.is_excluded(version, platform) then
                    local asset_name = self.expand(template, version)
                    local url = base .. "/" .. asset_name
                    table.insert(results, {
                        package  = self.pkg_name,
                        version  = version,
                        platform = platform,
                        url      = url,
                    })
                end
            end
        end
        return results
    end

    function self.check_link(asset)
        -- HEAD → GET フォールバック (CDN によっては HEAD 拒否)
        local status = curl_status("--head", asset.url)

        if status >= 400 or status == 0 then
            -- GET fallback: range request で帯域節約
            status = curl_status("-r", "0-1023", asset.url)
        end

        if status >= 200 and status < 400 then
            return {asset = asset, status = "ok", http_status = status, error = nil}
        else
            return {asset = asset, status = "fail", http_status = status,
                    error = ("HTTP %d"):format(status)}
        end
    end

    function self.discover_versions()
        if not self.update_check then return {} end

        local uc = self.update_check
        if uc.type == "github-release" then
            local gh = import("provider_github")
            local tmp = gh.new(self.pkg_name, {
                type        = "github-release",
                repo        = uc.repo,
                tag_pattern = uc.tag_pattern or "%(version)",
                versions    = self.versions,
                assets      = {},
                version_map = self.version_map,
            })
            return tmp.discover_versions()
        end

        return {}
    end

    return self
end

-- ファクトリに登録
provider_mod.register("http-direct", new)
```

---

## 6. Registry Layer: `registry.lua`

```lua
-- plugins/phc/modules/registry.lua

local SUPPORTED_SCHEMA = {1}
local RESERVED_KEYS = {_meta = true}

function load(filepath)
    if not os.isfile(filepath) then
        raise("registry file not found: %s", filepath)
    end

    local data, load_err = io.load(filepath)
    if not data then
        raise("failed to load registry: %s (%s)", filepath, tostring(load_err))
    end

    -- スキーマ検証
    local meta = data._meta or {}
    local sv = meta.schema_version
    if sv then
        local supported = false
        for _, v in ipairs(SUPPORTED_SCHEMA) do
            if v == sv then supported = true; break end
        end
        if not supported then
            raise("unsupported schema_version %d. supported: %s",
                sv, table.concat(SUPPORTED_SCHEMA, ", "))
        end
    end

    -- closure ベースの registry オブジェクトを返す
    local reg = {_data = data, _path = filepath}

    function reg.schema_version()
        return (data._meta or {}).schema_version or 1
    end

    function reg.package_names()
        local names = {}
        for k, _ in pairs(data) do
            if not RESERVED_KEYS[k] then
                table.insert(names, k)
            end
        end
        table.sort(names)
        return names
    end

    function reg.package_config(name)
        if RESERVED_KEYS[name] then
            raise("'%s' is reserved, not a package", name)
        end
        local config = data[name]
        if not config then
            raise("package '%s' not found in registry", name)
        end
        return config
    end

    function reg.filter(package_name)
        if package_name then
            reg.package_config(package_name)  -- 存在確認
            return {package_name}
        end
        return reg.package_names()
    end

    return reg
end
```

---

## 7. Checker Layer: `checker.lua`

```lua
-- plugins/phc/modules/checker.lua

local provider_mod = import("provider")

-- Provider モジュールをロードしてファクトリに登録
import("provider_github")
import("provider_http")

function check_links(registry, package_name)
    local results = {}
    local total, ok, fail, skipped = 0, 0, 0, 0

    for _, pkg_name in ipairs(registry.filter(package_name)) do
        local config = registry.package_config(pkg_name)
        if config.enabled == false then goto continue end

        local provider = provider_mod.create(pkg_name, config)
        local assets = provider.resolve_urls()

        for _, asset in ipairs(assets) do
            total = total + 1
            cprint("  ${dim}checking${clear} %s %s/%s ...", pkg_name, asset.version, asset.platform)

            local result = provider.check_link(asset)
            if result.status == "ok" then
                ok = ok + 1
                cprint("    ${green}✓${clear} %s", asset.url)
            else
                fail = fail + 1
                cprint("    ${red}✗${clear} %s (HTTP %s: %s)",
                    asset.url, tostring(result.http_status or "?"), result.error or "")
            end
            table.insert(results, {
                package     = result.asset.package,
                version     = result.asset.version,
                platform    = result.asset.platform,
                url         = result.asset.url,
                status      = result.status,
                http_status = result.http_status,
                error       = result.error,
            })
        end

        ::continue::
    end

    return {
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        results   = results,
        summary   = {total = total, ok = ok, fail = fail, skipped = skipped},
    }
end

function check_updates(registry, package_name)
    local updates = {}
    local has_any = false

    for _, pkg_name in ipairs(registry.filter(package_name)) do
        local config = registry.package_config(pkg_name)
        if config.enabled == false then goto continue end

        local provider = provider_mod.create(pkg_name, config)
        cprint("  ${dim}checking${clear} %s ...", pkg_name)

        local discovered = provider.discover_versions()
        local new_versions = {}
        for _, v in ipairs(discovered) do
            if v.is_new then
                table.insert(new_versions, v)
            end
        end

        local current_latest = config.versions[1]
        local entry = {
            package        = pkg_name,
            current_latest = current_latest,
            new_versions   = {},
            new_tags       = {},
            source         = _describe_source(config),
        }
        for _, v in ipairs(new_versions) do
            table.insert(entry.new_versions, v.version)
            table.insert(entry.new_tags, v.tag)
            cprint("    ${yellow}↑${clear} %s (tag: %s)", v.version, v.tag)
        end
        if #new_versions > 0 then has_any = true end

        table.insert(updates, entry)
        ::continue::
    end

    return {
        timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        updates     = updates,
        has_updates = has_any,
    }
end

function _describe_source(config)
    local ptype = config.type
    if ptype == "github-release" then
        return "github:" .. (config.repo or "?")
    elseif ptype == "http-direct" then
        local uc = config.update_check
        if uc and uc.repo then
            return "http-direct (via github:" .. uc.repo .. ")"
        end
        return "http-direct"
    end
    return ptype
end
```

---

## 8. Validator Layer: `validator.lua`

```lua
-- plugins/phc/modules/validator.lua

function validate(registry, packages_dir)
    local issues = {}

    for _, pkg_name in ipairs(registry.package_names()) do
        local config = registry.package_config(pkg_name)

        local first_letter = pkg_name:sub(1, 1):lower()
        local xmake_lua = path.join(packages_dir, first_letter, pkg_name, "xmake.lua")

        if not os.isfile(xmake_lua) then
            table.insert(issues, {
                package  = pkg_name,
                severity = "error",
                message  = ("xmake.lua not found: %s"):format(xmake_lua),
            })
            goto continue
        end

        local content = io.readfile(xmake_lua)

        -- バージョン整合性チェック
        local xmake_versions = {}
        for ver in content:gmatch('add_versions%(%s*"([^"]+)"') do
            if ver ~= "dev" then
                xmake_versions[ver] = true
            end
        end

        local registry_versions = {}
        for _, v in ipairs(config.versions) do
            registry_versions[v] = true
        end

        for v, _ in pairs(registry_versions) do
            if not xmake_versions[v] then
                table.insert(issues, {
                    package  = pkg_name,
                    severity = "error",
                    message  = ("version '%s' in packages.lua but not in xmake.lua"):format(v),
                })
            end
        end
        for v, _ in pairs(xmake_versions) do
            if not registry_versions[v] then
                table.insert(issues, {
                    package  = pkg_name,
                    severity = "warning",
                    message  = ("version '%s' in xmake.lua but not in packages.lua"):format(v),
                })
            end
        end

        _check_urls(pkg_name, config, content, issues)

        ::continue::
    end

    return issues
end

function _check_urls(pkg_name, config, content, issues)
    local ptype = config.type
    if ptype == "github-release" then
        local expected = ("github.com/%s/releases"):format(config.repo)
        if not content:find(expected, 1, true) then
            table.insert(issues, {
                package  = pkg_name,
                severity = "warning",
                message  = ("expected URL containing '%s' not found in xmake.lua"):format(expected),
            })
        end
    elseif ptype == "http-direct" then
        local base = config.base_url or ""
        local domain = base:match("https?://([^/]+)")
        if domain and not content:find(domain, 1, true) then
            table.insert(issues, {
                package  = pkg_name,
                severity = "warning",
                message  = ("expected URL domain '%s' not found in xmake.lua"):format(domain),
            })
        end
    end
end
```

---

## 9. Reporter Layer: `reporter.lua`

```lua
-- plugins/phc/modules/reporter.lua

import("core.base.json")

function print_link_report(report)
    cprint("${bright}[PHC] Link Check Report${clear}")
    cprint("")
    for _, r in ipairs(report.results) do
        local icon = r.status == "ok" and "${green}✓" or "${red}✗"
        cprint("  %s %s %s/%s${clear}  %s", icon, r.package, r.version, r.platform, r.url)
        if r.status ~= "ok" then
            cprint("    ${dim}→ %s${clear}", r.error or "unknown error")
        end
    end
    cprint("")
    cprint("  Summary: %d/%d OK", report.summary.ok, report.summary.total)
end

function print_update_report(report)
    cprint("${bright}[PHC] Update Check Report${clear}")
    cprint("")
    if report.has_updates then
        for _, u in ipairs(report.updates) do
            if #u.new_versions > 0 then
                cprint("  ${cyan}%s${clear} (current: %s)", u.package, u.current_latest)
                for _, v in ipairs(u.new_versions) do
                    cprint("    ${green}+ %s${clear}", v)
                end
            end
        end
    else
        cprint("  ${green}All packages up to date.${clear}")
    end
end

function print_validation_report(issues)
    cprint("${bright}[PHC] Validation Report${clear}")
    cprint("")
    if #issues == 0 then
        cprint("  ${green}✓ All packages consistent.${clear}")
        return
    end
    for _, issue in ipairs(issues) do
        local color = issue.severity == "error" and "red" or "yellow"
        cprint("  ${%s}[%s]${clear} %s: %s",
               color, issue.severity:upper(), issue.package, issue.message)
    end
    local errors, warnings = 0, 0
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then errors = errors + 1
        else warnings = warnings + 1 end
    end
    cprint("")
    cprint("  Summary: %d error(s), %d warning(s)", errors, warnings)
end

function save_json(filepath, data)
    local content = json.encode(data)
    io.writefile(filepath, content)
    cprint("${dim}Report saved to %s${clear}", filepath)
end
```

> **Note:** `cprint()` のカラーコードは `${green}`, `${red}`, `${bright}`, `${dim}`, `${clear}` 形式。
> `${color.green}` 形式は**動作しない**。

---

## 10. CLI エントリポイント: `task("phc")`

### 10.1 タスク定義

```lua
-- plugins/phc/xmake.lua

task("phc")
    set_category("plugin")

    on_run(function ()
        import("core.base.option")
        import("modules.registry")
        import("modules.checker")
        import("modules.validator")
        import("modules.reporter")

        local command = option.get("command")
        if not command then
            -- ヘルプ表示
            cprint("${bright}Package Health Check (PHC)${clear}")
            cprint("")
            cprint("Usage: xmake phc [options] <command>")
            cprint("")
            cprint("Commands:")
            cprint("  check-links     Check download link availability")
            cprint("  check-updates   Detect new upstream versions")
            cprint("  validate        Verify registry ↔ xmake.lua consistency")
            return
        end

        -- レジストリパス解決（優先順位: -r > scriptdir > ソースツリー > xmake-repo）
        -- ...
        local reg = registry.load(reg_path)
        local pkg_filter = option.get("package")
        local output = option.get("output")

        if command == "check-links" then
            local report = checker.check_links(reg, pkg_filter)
            if output then reporter.save_json(output, report) end
            if report.summary.fail > 0 then raise("broken links detected") end

        elseif command == "check-updates" then
            local report = checker.check_updates(reg, pkg_filter)
            if output then reporter.save_json(output, report) end

        elseif command == "validate" then
            local issues = validator.validate(reg, packages_dir)
            reporter.print_validation_report(issues)
        end
    end)

    set_menu {
        usage = "xmake phc [options] <command>",
        description = "Package Health Check — monitor download links & upstream versions",
        options = {
            -- kv options MUST come before positional "v"
            {'p', "package",      "kv", nil, "Check specific package only"},
            {'o', "output",       "kv", nil, "Write JSON report to file"},
            {'r', "registry",     "kv", nil, "Path to packages.lua"},
            {nil, "packages-dir", "kv", nil, "Path to packages/ directory (for validate)"},
            {nil, "command",      "v",  nil, "Subcommand: check-links, check-updates, validate"},
        }
    }
task_end()
```

### 10.2 使用例

```bash
# リンク切れ検知（全パッケージ）
xmake phc check-links

# 特定パッケージ + JSON 出力
xmake phc -p clang-arm -o link-report.json check-links

# 新バージョン検知
GITHUB_TOKEN=ghp_xxx xmake phc check-updates

# 整合性検証
xmake phc validate

# カスタムレジストリパス
xmake phc -r /path/to/packages.lua check-links
```

> **重要:** kv オプション (`-p`, `-o`, `-r`) はサブコマンドの**前**に配置する。
> `xmake phc -p renode check-links` ✓
> `xmake phc check-links -p renode` ✗

---

## 11. パッケージ定義: `xmake.lua`

```lua
-- packages/p/phc/xmake.lua

package("phc")
    set_kind("library")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("Package Health Check — xmake plugin for link & version monitoring")

    on_load(function (package)
        import("core.base.global")

        local src = os.scriptdir()
        local dest_plugin = path.join(global.directory(), "plugins", "phc")

        local function sync_tree(src_dir, dest_dir)
            if not os.isdir(src_dir) then return 0 end
            local count = 0
            for _, f in ipairs(os.files(path.join(src_dir, "**"))) do
                local rel = path.relative(f, src_dir)
                local dest_file = path.join(dest_dir, rel)
                os.mkdir(path.directory(dest_file))
                io.writefile(dest_file, io.readfile(f))
                count = count + 1
            end
            return count
        end

        if os.isdir(dest_plugin) then os.rmdir(dest_plugin) end

        local n = sync_tree(path.join(src, "plugins", "phc"), dest_plugin)
        n = n + sync_tree(path.join(src, "registry"),
                          path.join(dest_plugin, "registry"))

        cprint("${green}[phc]${clear} Plugin installed (%d files) → %s", n, dest_plugin)
    end)

    on_install(function (package) end)  -- メタパッケージ

    on_test(function (package)
        import("core.base.global")
        local phc_xmake = path.join(global.directory(), "plugins", "phc", "xmake.lua")
        assert(os.isfile(phc_xmake), "phc plugin not installed")
    end)
package_end()
```

---

## 12. GitHub Actions ワークフロー

### 12.1 `.github/workflows/check-packages.yml`

```yaml
name: Package Health Check

on:
  schedule:
    - cron: '0 9 * * 1'          # 毎週月曜 09:00 UTC
  workflow_dispatch:
    inputs:
      package:
        description: 'Check specific package (blank = all)'
        required: false
        type: string
  push:
    paths:
      - 'xmake-repo/synthernet/packages/p/phc/**'
      - 'xmake-repo/synthernet/packages/c/clang-arm/**'
      - 'xmake-repo/synthernet/packages/g/gcc-arm/**'
      - 'xmake-repo/synthernet/packages/r/renode/**'

env:
  PHC_DIR: xmake-repo/synthernet/packages/p/phc

jobs:
  validate:
    name: Validate Registry
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: xmake-io/github-action-setup-xmake@v1
      - name: Install PHC plugin
        run: |
          mkdir -p ~/.xmake/plugins/phc
          cp -r ${{ env.PHC_DIR }}/plugins/phc/* ~/.xmake/plugins/phc/
          cp -r ${{ env.PHC_DIR }}/registry ~/.xmake/plugins/phc/
      - run: xmake phc validate -r ${{ env.PHC_DIR }}/registry/packages.lua

  check-links:
    name: Check Download Links
    runs-on: ubuntu-latest
    needs: validate
    # ...

  check-updates:
    name: Check Upstream Updates
    runs-on: ubuntu-latest
    needs: validate
    # ...

  notify:
    name: Create Issue on Detection
    runs-on: ubuntu-latest
    needs: [check-links, check-updates]
    if: needs.check-links.outputs.has_failures == 'true' || needs.check-updates.outputs.has_updates == 'true'
    # ...
```

完全なワークフローファイルは `.github/workflows/check-packages.yml` を参照。

---

## 13. 新しい Provider の追加手順

### 13.1 例: PyPI Provider

**Step 1: `modules/provider_pypi.lua` を作成**

```lua
local provider_mod = import("provider")

function new(pkg_name, config)
    local self = provider_mod.new_base(pkg_name, config)
    self.pypi_name = config.pypi_name

    function self.resolve_urls() ... end
    function self.check_link(asset) ... end
    function self.discover_versions() ... end

    return self
end

provider_mod.register("pypi", new)
```

**Step 2: `checker.lua` に `import("provider_pypi")` を追加**

**Step 3: `packages.lua` にデータ追加**

### 13.2 チェックリスト

- [ ] 3 つのメソッド (`resolve_urls`, `check_link`, `discover_versions`) を closure で実装
- [ ] `provider_mod.register()` でファクトリに登録
- [ ] `checker.lua` に `import` を追加
- [ ] `packages.lua` にテストエントリを追加
- [ ] 全 3 コマンドで動作確認

---

## 14. 新しいパッケージの追加手順

**コード変更不要。** `packages.lua` にエントリを追加するだけ。

```bash
xmake phc validate
xmake phc -p <name> check-links
```

---

## 15. 運用ガイド

### 15.1 ローカル開発（プラグイン直接インストール）

```bash
rm -rf ~/.xmake/plugins/phc
mkdir -p ~/.xmake/plugins/phc
cp -R xmake-repo/synthernet/packages/p/phc/plugins/phc/* ~/.xmake/plugins/phc/
cp -R xmake-repo/synthernet/packages/p/phc/registry ~/.xmake/plugins/phc/
```

### 15.2 新バージョン追加フロー

```
1. Issue 確認 → 新バージョン番号を把握
2. packages.lua: versions, version_map, exclusions を更新
3. packages/<pkg>/xmake.lua: add_versions() + SHA256
4. xmake phc validate && xmake phc -p <name> check-links
5. PR → CI → マージ → Issue クローズ
```

---

## Appendix A: 既存 CI との関係

| ワークフロー | 役割 | 関係 |
|-------------|------|------|
| `ci.yml` | lib/ ビルド＆テスト | 無関係 |
| `release.yml` | ライブラリアーカイブ生成 | 補完（SHA256 提供） |
| `doxygen.yml` | API ドキュメント | 無関係 |
| **`check-packages.yml`** | パッケージヘルスチェック | **本仕様** |

## Appendix B: 設計判断 (ADR)

### B.1 Lua テーブル vs TOML → Lua テーブル (`io.load()`)

`io.load()` は `return` なし、コメントなしのフォーマットのみ受け付ける。

### B.2 curl vs net.http → curl (`os.iorunv`)

REST API の JSON レスポンス取得には `curl -sS` が確実。

### B.3 packages.lua と xmake.lua の二重管理 → `validate` で整合性保証

xmake.lua は Lua ロジックを含み宣言的データでは表現不可能。

### B.4 プラグイン配布 → `on_load()` + `sync_tree()` → `~/.xmake/plugins/`

`arm-embedded` と同じパターン。

### B.5 クラス OOP vs Closure → Closure ベース

xmake sandbox で `setmetatable` 不可。

### B.6 エラーハンドリング → `raise()` + `try-catch`

xmake sandbox で `error()` / `pcall()` 不可。
