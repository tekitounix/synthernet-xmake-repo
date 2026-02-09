-- plugins/phc/modules/updater.lua
--
-- パッケージの自動更新ロジック。
-- 新バージョンを検出 → アセットをダウンロード → SHA256 計算 → packages.lua 更新。

local provider_mod = import("provider")

---------------------------------------------------------------
-- update_package: 指定パッケージの新バージョンを追加
---------------------------------------------------------------
function update_package(registry, pkg_name, opts)
    opts = opts or {}
    local config = registry.package_config(pkg_name)
    local provider = provider_mod.create(pkg_name, config)

    local target_version = opts.version
    local results = {}

    -- 1. バージョン検出
    if target_version then
        -- 指定バージョンが既に存在するかチェック
        for _, v in ipairs(config.versions) do
            if v == target_version then
                cprint("  ${dim}%s %s already registered${clear}", pkg_name, target_version)
                if not opts.force then
                    return {status = "skipped", reason = "already registered"}
                end
            end
        end
        results.versions = {{version = target_version, is_new = true}}
    else
        -- 新バージョンを自動検出
        cprint("  ${dim}discovering versions for %s...${clear}", pkg_name)
        local discovered = provider.discover_versions()
        local new_versions = {}
        for _, v in ipairs(discovered) do
            if v.is_new then
                table.insert(new_versions, v)
            end
        end
        if #new_versions == 0 then
            cprint("  ${green}✓${clear} %s is up to date", pkg_name)
            return {status = "up_to_date"}
        end
        results.versions = new_versions
    end

    -- 2. 各新バージョンのハッシュを計算
    local hash_policy = (config.install_config or {}).hash_policy
    local all_hashes = {}

    for _, ver_info in ipairs(results.versions) do
        local version = ver_info.version
        cprint("  ${yellow}↑${clear} %s %s", pkg_name, version)

        if hash_policy == "dummy" then
            -- ハッシュ不要
            cprint("    ${dim}hash_policy=dummy, skipping download${clear}")
            all_hashes[version] = {}
        else
            -- バージョンに応じたソースから assets を取得
            local src = provider_mod.resolve_source(config, version)
            local version_assets = src.assets or config.assets

            -- 各プラットフォームのアセットをダウンロードしてSHA256計算
            local version_hashes = {}
            for platform_id, asset_template in pairs(version_assets) do
                -- exclusion チェック
                local excluded = false
                if config.exclusions and config.exclusions[version] then
                    for _, ep in ipairs(config.exclusions[version]) do
                        if ep == platform_id then excluded = true; break end
                    end
                end
                if excluded then
                    cprint("    ${dim}skip${clear} %s/%s (excluded)", version, platform_id)
                    goto continue_platform
                end

                -- URL 構築
                local url = _build_download_url(config, version, platform_id, asset_template)
                if not url then
                    cprint("    ${red}✗${clear} %s/%s — cannot build URL", version, platform_id)
                    goto continue_platform
                end

                cprint("    ${dim}downloading${clear} %s/%s...", version, platform_id)

                -- ダウンロード + SHA256
                local hash = _download_and_hash(url, pkg_name, version, platform_id)
                if hash then
                    version_hashes[platform_id] = hash
                    cprint("    ${green}✓${clear} %s/%s → %s", version, platform_id, hash:sub(1, 16) .. "...")
                else
                    cprint("    ${red}✗${clear} %s/%s — download failed", version, platform_id)
                    return {status = "error", reason = format("download failed: %s/%s", version, platform_id)}
                end

                ::continue_platform::
            end
            all_hashes[version] = version_hashes
        end
    end

    results.hashes = all_hashes
    results.status = "success"
    return results
end

---------------------------------------------------------------
-- apply_update: packages.lua に結果を書き込む
---------------------------------------------------------------
function apply_update(registry, pkg_name, update_result, packages_lua_path)
    if update_result.status ~= "success" then return false end

    local data = io.load(packages_lua_path)
    if not data then
        raise("cannot load packages.lua: %s", packages_lua_path)
    end

    local config = data[pkg_name]
    if not config then
        raise("package '%s' not found in packages.lua", pkg_name)
    end

    -- versions に新バージョンを先頭に追加
    for _, ver_info in ipairs(update_result.versions) do
        local version = ver_info.version
        -- 重複チェック
        local exists = false
        for _, v in ipairs(config.versions) do
            if v == version then exists = true; break end
        end
        if not exists then
            -- 先頭に挿入（最新が先頭）
            table.insert(config.versions, 1, version)
        end
    end

    -- hashes を更新
    if not config.hashes then config.hashes = {} end
    for version, platform_hashes in pairs(update_result.hashes) do
        if not config.hashes[version] then
            config.hashes[version] = {}
        end
        for pid, hash in pairs(platform_hashes) do
            config.hashes[version][pid] = hash
        end
    end

    -- packages.lua にシリアライズして書き戻す
    _serialize_packages(data, packages_lua_path)

    return true
end

---------------------------------------------------------------
-- ヘルパー: ダウンロードURL構築 (source_overrides 対応)
---------------------------------------------------------------
function _build_download_url(config, version, platform_id, asset_template)
    local src = provider_mod.resolve_source(config, version)
    local mapped_version = version
    if config.version_map and config.version_map[version] then
        mapped_version = config.version_map[version]
    end

    local filename = asset_template:gsub("%%%(version%)", version):gsub("%%%(mapped_version%)", mapped_version)

    if src.type == "github-release" then
        local tag = src.tag_pattern:gsub("%%%(version%)", version)
        return format("https://github.com/%s/releases/download/%s/%s", src.repo, tag, filename)
    elseif src.type == "http-direct" then
        local base = src.base_url:gsub("%%%(mapped_version%)", mapped_version):gsub("%%%(version%)", version)
        return format("%s/%s", base, filename)
    end
    return nil
end

---------------------------------------------------------------
-- ヘルパー: ダウンロード + SHA256
---------------------------------------------------------------
function _download_and_hash(url, pkg_name, version, platform_id)
    import("net.http")

    local tmpdir = os.tmpdir()
    local filename = format("%s_%s_%s", pkg_name, version, platform_id:gsub("[^%w]", "_"))
    local tmpfile = path.join(tmpdir, filename)

    -- ダウンロード
    local download_ok = try { function()
        http.download(url, tmpfile)
        return true
    end }

    if not download_ok or not os.isfile(tmpfile) then
        return nil
    end

    -- SHA256 計算
    local hash = _compute_sha256(tmpfile)

    -- 一時ファイル削除
    try { function() os.rm(tmpfile) end }

    return hash
end

---------------------------------------------------------------
-- ヘルパー: SHA256 計算
---------------------------------------------------------------
function _compute_sha256(filepath)
    import("lib.detect.find_tool")

    -- shasum (macOS/Linux)
    local shasum = find_tool("shasum")
    if shasum then
        local result = os.iorunv(shasum.program, {"-a", "256", filepath})
        if result then
            return result:split("%s+")[1]
        end
    end

    -- sha256sum (Linux)
    local sha256sum = find_tool("sha256sum")
    if sha256sum then
        local result = os.iorunv(sha256sum.program, {filepath})
        if result then
            return result:split("%s+")[1]
        end
    end

    -- certutil (Windows)
    local certutil = find_tool("certutil")
    if certutil then
        local result = os.iorunv(certutil.program, {"-hashfile", filepath, "SHA256"})
        if result then
            local lines_result = result:split("\n")
            if #lines_result >= 2 then
                return lines_result[2]:trim()
            end
        end
    end

    raise("no SHA256 tool found (shasum, sha256sum, or certutil)")
end

---------------------------------------------------------------
-- ヘルパー: packages.lua のシリアライズ
---------------------------------------------------------------
function _serialize_packages(data, filepath)
    local lines = {}

    local function emit(s) table.insert(lines, s) end
    local function indent(level) return string.rep("    ", level) end

    -- table keys をソートして出力
    local function serialize_value(val, level)
        if type(val) == "string" then
            return format('"%s"', val)
        elseif type(val) == "number" then
            return tostring(val)
        elseif type(val) == "boolean" then
            return tostring(val)
        elseif type(val) == "table" then
            -- 配列かどうか判定
            local is_array = true
            local max_i = 0
            for k, _ in pairs(val) do
                if type(k) ~= "number" then is_array = false; break end
                if k > max_i then max_i = k end
            end
            if is_array and max_i == #val then
                -- 短い配列は1行で
                if max_i <= 4 then
                    local items = {}
                    for _, v in ipairs(val) do
                        table.insert(items, serialize_value(v, level + 1))
                    end
                    return "{" .. table.concat(items, ", ") .. "}"
                end
            end
            return nil -- テーブルは別途処理
        end
        return tostring(val)
    end

    local function serialize_table(tbl, level)
        local keys = {}
        for k, _ in pairs(tbl) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b)
            if type(a) ~= type(b) then
                return type(a) < type(b)
            end
            return a < b
        end)

        emit(indent(level) .. "{")

        for _, k in ipairs(keys) do
            local v = tbl[k]
            local key_str
            if type(k) == "string" then
                if k:match("^[%a_][%w_]*$") then
                    key_str = k
                else
                    key_str = format('["%s"]', k)
                end
            else
                key_str = format("[%s]", tostring(k))
            end

            local simple = serialize_value(v, level + 1)
            if simple then
                emit(format("%s%s = %s,", indent(level + 1), key_str, simple))
            else
                -- nested table
                emit(format("%s%s = {", indent(level + 1), key_str))
                -- recurse
                local sub_keys = {}
                for sk, _ in pairs(v) do table.insert(sub_keys, sk) end
                table.sort(sub_keys, function(a, b)
                    if type(a) ~= type(b) then return type(a) < type(b) end
                    return a < b
                end)
                for _, sk in ipairs(sub_keys) do
                    local sv = v[sk]
                    local skey_str
                    if type(sk) == "string" then
                        if sk:match("^[%a_][%w_]*$") then
                            skey_str = sk
                        else
                            skey_str = format('["%s"]', sk)
                        end
                    else
                        skey_str = format("[%s]", tostring(sk))
                    end
                    local ssimple = serialize_value(sv, level + 2)
                    if ssimple then
                        emit(format("%s%s = %s,", indent(level + 2), skey_str, ssimple))
                    else
                        emit(format("%s%s = {", indent(level + 2), skey_str))
                        local sub2_keys = {}
                        for s2k, _ in pairs(sv) do table.insert(sub2_keys, s2k) end
                        table.sort(sub2_keys, function(a, b)
                            if type(a) ~= type(b) then return type(a) < type(b) end
                            return a < b
                        end)
                        for _, s2k in ipairs(sub2_keys) do
                            local s2v = sv[s2k]
                            local s2key_str
                            if type(s2k) == "string" then
                                if s2k:match("^[%a_][%w_]*$") then
                                    s2key_str = s2k
                                else
                                    s2key_str = format('["%s"]', s2k)
                                end
                            else
                                s2key_str = format("[%s]", tostring(s2k))
                            end
                            local s2simple = serialize_value(s2v, level + 3)
                            if s2simple then
                                emit(format("%s%s = %s,", indent(level + 3), s2key_str, s2simple))
                            end
                        end
                        emit(format("%s},", indent(level + 2)))
                    end
                end
                emit(format("%s},", indent(level + 1)))
            end
        end

        emit(indent(level) .. "}")
    end

    -- _meta を先に、パッケージをアルファベット順に
    emit("{")

    -- _meta
    if data._meta then
        emit('    _meta = {')
        if data._meta.schema_version then
            emit(format('        schema_version = %d,', data._meta.schema_version))
        end
        if data._meta.description then
            emit(format('        description = "%s"', data._meta.description))
        end
        emit('    },')
    end

    -- パッケージ
    local pkg_names = {}
    for k, _ in pairs(data) do
        if k ~= "_meta" then table.insert(pkg_names, k) end
    end
    table.sort(pkg_names)

    for _, name in ipairs(pkg_names) do
        local pkg = data[name]
        emit(format('    ["%s"] = {', name))

        -- type
        if pkg.type then emit(format('        type = "%s",', pkg.type)) end
        -- repo
        if pkg.repo then emit(format('        repo = "%s",', pkg.repo)) end
        -- base_url
        if pkg.base_url then emit(format('        base_url = "%s",', pkg.base_url)) end
        -- tag_pattern
        if pkg.tag_pattern then emit(format('        tag_pattern = "%s",', pkg.tag_pattern)) end
        -- fallback_tag_pattern
        if pkg.fallback_tag_pattern then emit(format('        fallback_tag_pattern = "%s",', pkg.fallback_tag_pattern)) end
        -- update_check
        if pkg.update_check then
            emit('        update_check = {')
            if pkg.update_check.type then emit(format('            type = "%s",', pkg.update_check.type)) end
            if pkg.update_check.repo then emit(format('            repo = "%s"', pkg.update_check.repo)) end
            emit('        },')
        end
        -- source_overrides
        if pkg.source_overrides then
            emit('        source_overrides = {')
            for _, override in ipairs(pkg.source_overrides) do
                emit('            {')
                if override.version_ge then emit(format('                version_ge = "%s",', override.version_ge)) end
                if override.repo then emit(format('                repo = "%s",', override.repo)) end
                if override.tag_pattern then emit(format('                tag_pattern = "%s",', override.tag_pattern)) end
                if override.fallback_tag_pattern ~= nil then
                    if override.fallback_tag_pattern == false then
                        emit('                fallback_tag_pattern = false,')
                    else
                        emit(format('                fallback_tag_pattern = "%s",', override.fallback_tag_pattern))
                    end
                end
                if override.discover_from then emit('                discover_from = true,') end
                if override.assets then
                    emit('                assets = {')
                    local okeys = {}
                    for k, _ in pairs(override.assets) do table.insert(okeys, k) end
                    table.sort(okeys)
                    for _, k in ipairs(okeys) do
                        emit(format('                    ["%s"] = "%s",', k, override.assets[k]))
                    end
                    emit('                },')
                end
                emit('            },')
            end
            emit('        },')
        end
        -- versions
        if pkg.versions then
            local ver_strs = {}
            for _, v in ipairs(pkg.versions) do table.insert(ver_strs, format('"%s"', v)) end
            emit(format('        versions = {%s},', table.concat(ver_strs, ", ")))
        end
        -- version_map
        if pkg.version_map then
            emit('        version_map = {')
            local vm_keys = {}
            for k, _ in pairs(pkg.version_map) do table.insert(vm_keys, k) end
            table.sort(vm_keys)
            for _, k in ipairs(vm_keys) do
                emit(format('            ["%s"] = "%s",', k, pkg.version_map[k]))
            end
            emit('        },')
        end
        -- assets
        if pkg.assets then
            emit('        assets = {')
            local asset_keys = {}
            for k, _ in pairs(pkg.assets) do table.insert(asset_keys, k) end
            table.sort(asset_keys)
            for _, k in ipairs(asset_keys) do
                emit(format('            ["%s"] = "%s",', k, pkg.assets[k]))
            end
            emit('        },')
        end
        -- exclusions
        if pkg.exclusions then
            emit('        exclusions = {')
            for ver, platforms in pairs(pkg.exclusions) do
                local pstrs = {}
                for _, p in ipairs(platforms) do table.insert(pstrs, format('"%s"', p)) end
                emit(format('            ["%s"] = {%s}', ver, table.concat(pstrs, ", ")))
            end
            emit('        },')
        end
        -- metadata
        if pkg.metadata then
            emit('        metadata = {')
            if pkg.metadata.kind then emit(format('            kind = "%s",', pkg.metadata.kind)) end
            if pkg.metadata.homepage then emit(format('            homepage = "%s",', pkg.metadata.homepage)) end
            if pkg.metadata.description then emit(format('            description = "%s"', pkg.metadata.description)) end
            emit('        },')
        end
        -- install
        if pkg.install then emit(format('        install = "%s",', pkg.install)) end
        -- install_config
        if pkg.install_config then
            emit('        install_config = {')
            local ic = pkg.install_config
            if ic.bin_verify then
                local bv = {}
                for _, v in ipairs(ic.bin_verify) do table.insert(bv, format('"%s"', v)) end
                emit(format('            bin_verify = {%s},', table.concat(bv, ", ")))
            end
            if ic.toolchain_def then emit(format('            toolchain_def = "%s",', ic.toolchain_def)) end
            if ic.bin_check then emit(format('            bin_check = "%s",', ic.bin_check)) end
            if ic.dmg_search_pattern then
                if type(ic.dmg_search_pattern) == "table" then
                    local dsp = {}
                    for _, p in ipairs(ic.dmg_search_pattern) do table.insert(dsp, format('"%s"', p)) end
                    emit(format('            dmg_search_pattern = {%s},', table.concat(dsp, ", ")))
                else
                    emit(format('            dmg_search_pattern = "%s",', ic.dmg_search_pattern))
                end
            end
            if ic.custom_download then emit('            custom_download = true,') end
            if ic.hash_policy then emit(format('            hash_policy = "%s",', ic.hash_policy)) end
            if ic.download_size then emit(format('            download_size = "%s",', ic.download_size)) end
            if ic.install_size then emit(format('            install_size = "%s",', ic.install_size)) end
            if ic.wrapper then
                emit('            wrapper = {')
                if ic.wrapper.name then emit(format('                name = "%s",', ic.wrapper.name)) end
                if ic.wrapper.windows_name then emit(format('                windows_name = "%s"', ic.wrapper.windows_name)) end
                emit('            },')
            end
            if ic.macos_app then emit(format('            macos_app = "%s"', ic.macos_app)) end
            emit('        },')
        end
        -- hashes
        if pkg.hashes then
            emit('        hashes = {')
            local h_versions = {}
            for v, _ in pairs(pkg.hashes) do table.insert(h_versions, v) end
            table.sort(h_versions, function(a, b) return a > b end) -- 新しいバージョンが先
            for _, v in ipairs(h_versions) do
                local platforms = pkg.hashes[v]
                emit(format('            ["%s"] = {', v))
                local pkeys = {}
                for pk, _ in pairs(platforms) do table.insert(pkeys, pk) end
                table.sort(pkeys)
                for _, pk in ipairs(pkeys) do
                    emit(format('                ["%s"] = "%s",', pk, platforms[pk]))
                end
                emit('            },')
            end
            emit('        }')
        end

        emit('    },')
    end

    emit('}')
    emit('')

    io.writefile(filepath, table.concat(lines, "\n"))
end
