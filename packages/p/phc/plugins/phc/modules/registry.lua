-- plugins/phc/modules/registry.lua
--
-- packages.lua の読み込みとスキーマ検証。
-- xmake サンドボックス: setmetatable 不可、import() は非ローカル関数をエクスポート。

local SUPPORTED_SCHEMA = {1, 2}
local RESERVED_KEYS = {_meta = true}

function load(filepath)
    if not os.isfile(filepath) then
        raise("registry file not found: %s", filepath)
    end

    -- packages.lua はシリアライズされた Lua テーブル
    -- xmake の io.load() で読み込む
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
            -- validate the package exists
            reg.package_config(package_name)
            return {package_name}
        end
        return reg.package_names()
    end

    return reg
end
