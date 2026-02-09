-- plugins/phc/modules/provider.lua
--
-- Provider ベースファクトリとユーティリティ。
-- xmake サンドボックスでは setmetatable 不可のため closure ベース。
-- xmake import() はモジュールスコープの非ローカル関数をエクスポートする。

-------------------------------------------------------------------
-- ファクトリレジストリ (モジュールスコープ)
-------------------------------------------------------------------
REGISTRY = {}
local _discovered = false

function register(type_name, constructor)
    REGISTRY[type_name] = constructor
end

--- modules/ 内の provider_*.lua を動的にスキャンして自動登録。
-- 新 Provider は provider_<name>.lua を追加するだけで認識される。
function auto_discover()
    if _discovered then return end
    _discovered = true

    local modules_dir = path.join(os.scriptdir())
    for _, f in ipairs(os.files(path.join(modules_dir, "provider_*.lua"))) do
        local mod_name = path.basename(f)
        import(mod_name)
    end
end

function create(pkg_name, config)
    auto_discover()
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

    --- Provider のソースを人間可読な文字列で返す。
    -- 各 Provider が上書きする。デフォルトは type 名をそのまま返す。
    function self.describe_source()
        return config.type
    end

    return self
end

-------------------------------------------------------------------
-- バージョン比較: a >= b (セマンティックバージョン)
-------------------------------------------------------------------
function version_gte(a, b)
    local function split(s)
        local parts = {}
        for p in s:gmatch("(%d+)") do
            table.insert(parts, tonumber(p))
        end
        return parts
    end
    local pa, pb = split(a), split(b)
    for i = 1, math.max(#pa, #pb) do
        local ai, bi = pa[i] or 0, pb[i] or 0
        if ai > bi then return true end
        if ai < bi then return false end
    end
    return true  -- equal
end

-------------------------------------------------------------------
-- バージョンに対応するソース情報を解決
-- source_overrides がなければトップレベルの設定をそのまま返す
-------------------------------------------------------------------
function resolve_source(config, version)
    if config.source_overrides then
        for _, override in ipairs(config.source_overrides) do
            if override.version_ge and version_gte(version, override.version_ge) then
                -- fallback_tag_pattern: false で明示的無効化に対応
                -- Lua の and/or は false を falsy 扱いするため三項演算子パターン不可
                local ftp = config.fallback_tag_pattern
                if override.fallback_tag_pattern ~= nil then
                    ftp = override.fallback_tag_pattern
                end
                return {
                    repo = override.repo or config.repo,
                    tag_pattern = override.tag_pattern or config.tag_pattern,
                    fallback_tag_pattern = ftp,
                    assets = override.assets or config.assets,
                    base_url = override.base_url or config.base_url,
                    type = config.type,
                }
            end
        end
    end
    return {
        repo = config.repo,
        tag_pattern = config.tag_pattern,
        fallback_tag_pattern = config.fallback_tag_pattern,
        assets = config.assets,
        base_url = config.base_url,
        type = config.type,
    }
end

-------------------------------------------------------------------
-- バージョンをソースごとにグループ化 (出現順を維持)
-------------------------------------------------------------------
function group_versions_by_source(config)
    local groups = {}
    local key_to_index = {}

    for _, version in ipairs(config.versions or {}) do
        local src = resolve_source(config, version)
        local key = (src.repo or "") .. "|" .. (src.tag_pattern or "") .. "|" .. (src.base_url or "")
        local idx = key_to_index[key]
        if idx then
            table.insert(groups[idx].versions, version)
        else
            table.insert(groups, {source = src, versions = {version}})
            key_to_index[key] = #groups
        end
    end
    return groups
end
