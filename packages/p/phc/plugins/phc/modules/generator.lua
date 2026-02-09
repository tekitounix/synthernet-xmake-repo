-- plugins/phc/modules/generator.lua
--
-- packages.lua (schema v2) から xmake.lua を完全生成するエンジン。
-- install テンプレートモジュールをロードして on_install/on_load/on_test を生成。

---------------------------------------------------------------
-- プラットフォームID → xmake host/arch 条件マッピング
---------------------------------------------------------------
local PLATFORM_MAP = {
    ["linux-x86_64"]     = {host = "linux",   arch_check = nil,                          arch_neg = nil},
    ["linux-aarch64"]    = {host = "linux",   arch_check = 'os.arch():find("arm64")',    arch_neg = nil},
    ["windows-x86_64"]   = {host = "windows", arch_check = nil,                          arch_neg = nil},
    ["windows-x86"]      = {host = "windows", arch_check = 'os.arch() == "x86"',         arch_neg = nil},
    ["macos-universal"]  = {host = "macosx",  arch_check = nil,                          arch_neg = nil},
    ["macos-arm64"]      = {host = "macosx",  arch_check = nil,                          arch_neg = nil},
    ["macos-x86_64"]     = {host = "macosx",  arch_check = 'os.arch() ~= "arm64"',      arch_neg = nil},
    ["windows-portable"] = {host = "windows", arch_check = nil,                          arch_neg = nil},
}

---------------------------------------------------------------
-- ヘルパー: プラットフォームIDをホストごとにグループ化
---------------------------------------------------------------
local function group_platforms_by_host(platform_ids)
    local groups = {}
    local host_order = {"linux", "windows", "macosx"}
    local seen = {}
    for _, pid in ipairs(platform_ids) do
        local pm = PLATFORM_MAP[pid]
        if pm then
            if not groups[pm.host] then
                groups[pm.host] = {}
            end
            table.insert(groups[pm.host], {id = pid, arch_check = pm.arch_check})
            seen[pm.host] = true
        end
    end
    local ordered = {}
    for _, h in ipairs(host_order) do
        if seen[h] then
            table.insert(ordered, {host = h, platforms = groups[h]})
        end
    end
    return ordered
end

---------------------------------------------------------------
-- ヘルパー: URL テンプレート生成
---------------------------------------------------------------
local function build_url(config, platform_id, version)
    local asset_template = config.assets[platform_id]
    if not asset_template then return nil end

    local mapped_version = version
    if config.version_map and config.version_map[version] then
        mapped_version = config.version_map[version]
    end

    local filename = asset_template:gsub("%%%(version%)", version):gsub("%%%(mapped_version%)", mapped_version)

    if config.type == "github-release" then
        local tag = config.tag_pattern:gsub("%%%(version%)", version)
        return format("https://github.com/%s/releases/download/%s/%s", config.repo, tag, filename)
    elseif config.type == "http-direct" then
        local base = config.base_url:gsub("%%%(mapped_version%)", mapped_version):gsub("%%%(version%)", version)
        return format("%s/%s", base, filename)
    end
    return nil
end

---------------------------------------------------------------
-- ヘルパー: xmake URL テンプレート ($(version) 形式)
---------------------------------------------------------------
local function build_xmake_url_template(config, platform_id)
    local asset_template = config.assets[platform_id]
    if not asset_template then return nil end

    -- $(version) は xmake が version 関数経由で置換する
    local filename = asset_template:gsub("%%%(version%)", "$(version)"):gsub("%%%(mapped_version%)", "$(version)")

    if config.type == "github-release" then
        local tag = config.tag_pattern:gsub("%%%(version%)", "$(version)")
        local url = format("https://github.com/%s/releases/download/%s/%s", config.repo, tag, filename)
        -- fallback URL
        if config.fallback_tag_pattern then
            local fallback_tag = config.fallback_tag_pattern:gsub("%%%(version%)", "$(version)")
            local fallback_url = format("https://github.com/%s/releases/download/%s/%s", config.repo, fallback_tag, filename)
            return url, fallback_url
        end
        return url
    elseif config.type == "http-direct" then
        local base = config.base_url:gsub("%%%(mapped_version%)", "$(version)"):gsub("%%%(version%)", "$(version)")
        return format("%s/%s", base, filename)
    end
    return nil
end

---------------------------------------------------------------
-- ヘルパー: ソース情報から xmake URL テンプレート生成
-- source_overrides 対応: resolve_source() が返す src を受け取る
---------------------------------------------------------------
local function build_xmake_url_for_source(src, platform_id)
    local asset_template = src.assets and src.assets[platform_id]
    if not asset_template then return nil end

    local filename = asset_template:gsub("%%%(version%)", "$(version)"):gsub("%%%(mapped_version%)", "$(version)")

    if src.type == "github-release" then
        local tag = src.tag_pattern:gsub("%%%(version%)", "$(version)")
        local url = format("https://github.com/%s/releases/download/%s/%s", src.repo, tag, filename)
        if src.fallback_tag_pattern then
            local fallback_tag = src.fallback_tag_pattern:gsub("%%%(version%)", "$(version)")
            local fallback_url = format("https://github.com/%s/releases/download/%s/%s", src.repo, fallback_tag, filename)
            return url, fallback_url
        end
        return url
    elseif src.type == "http-direct" then
        local base = src.base_url:gsub("%%%(mapped_version%)", "$(version)"):gsub("%%%(version%)", "$(version)")
        return format("%s/%s", base, filename)
    end
    return nil
end

---------------------------------------------------------------
-- ヘルパー: exclusion チェック
---------------------------------------------------------------
local function is_excluded(config, version, platform_id)
    if not config.exclusions then return false end
    local excl = config.exclusions[version]
    if not excl then return false end
    for _, pid in ipairs(excl) do
        if pid == platform_id then return true end
    end
    return false
end

---------------------------------------------------------------
-- ヘルパー: version_map を使う場合の version 関数コード
---------------------------------------------------------------
local function version_map_code(config)
    if not config.version_map then return nil end
    local lines = {}
    table.insert(lines, "    local version_map = {")
    local keys = {}
    for k, _ in pairs(config.version_map) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        table.insert(lines, format('        ["%s"] = "%s",', k, config.version_map[k]))
    end
    table.insert(lines, "    }")
    return table.concat(lines, "\n")
end

---------------------------------------------------------------
-- install テンプレートのロード
---------------------------------------------------------------
local _templates = {}

local function load_template(name)
    if _templates[name] then return _templates[name] end
    local mod = import("install_" .. name:gsub("%-", "_"))
    _templates[name] = mod
    return mod
end

---------------------------------------------------------------
-- generate: 1パッケージの xmake.lua を生成
---------------------------------------------------------------
function generate(pkg_name, config)
    local lines = {}
    local function emit(s, a1, a2, a3, a4)
        if a1 ~= nil then
            s = format(s, a1, a2, a3, a4)
        end
        table.insert(lines, s)
    end

    local meta = config.metadata or {}
    local ic = config.install_config or {}

    -- ── header ──
    emit('package("%s")', pkg_name)
    emit('')
    emit('    set_kind("%s")', meta.kind or "binary")
    emit('    set_homepage("%s")', meta.homepage or "")
    emit('    set_description("%s")', meta.description or "")

    -- ── version_map (if needed) ──
    local vm_code = version_map_code(config)
    if vm_code then
        emit('')
        emit('%s', vm_code)
    end

    -- ── platform-specific URLs + versions ──
    emit('')
    -- 全ソース (デフォルト + source_overrides) からプラットフォームIDを集約
    local platform_set = {}
    for pid, _ in pairs(config.assets) do
        platform_set[pid] = true
    end
    if config.source_overrides then
        for _, override in ipairs(config.source_overrides) do
            if override.assets then
                for pid, _ in pairs(override.assets) do
                    platform_set[pid] = true
                end
            end
        end
    end
    local sorted_platforms = {}
    for pid, _ in pairs(platform_set) do
        table.insert(sorted_platforms, pid)
    end
    table.sort(sorted_platforms)

    local groups = group_platforms_by_host(sorted_platforms)
    local first_group = true

    for _, group in ipairs(groups) do
        local host = group.host
        local platforms = group.platforms

        -- ホスト間の分岐を生成
        if first_group then
            first_group = false
        end

        -- arch 分岐が必要なプラットフォームとそうでないものを分離
        local arch_platforms = {}
        local default_platform = nil
        for _, p in ipairs(platforms) do
            if p.arch_check then
                table.insert(arch_platforms, p)
            else
                default_platform = p
            end
        end

        -- 単一プラットフォームの場合
        if #platforms == 1 then
            local p = platforms[1]
            local condition
            if p.arch_check then
                condition = format('is_host("%s") and %s', host, p.arch_check)
            else
                condition = format('is_host("%s")', host)
            end

            if first_group == false and lines[#lines] ~= "" then
                -- elseif chain
            end

            local prefix = (groups[1] == group) and "    if " or "    elseif "
            emit('%s%s then', prefix, condition)
            _emit_platform_block(emit, config, p.id, ic)
        elseif #arch_platforms > 0 then
            -- 複数 arch 分岐
            local prefix = (groups[1] == group) and "    if " or "    elseif "

            if #arch_platforms == 1 and default_platform then
                -- arch_check があるものを先に、残りを else
                emit('%sis_host("%s") then', prefix, host)
                emit('        if %s then', arch_platforms[1].arch_check)
                _emit_platform_block(emit, config, arch_platforms[1].id, ic, "            ")
                emit('        else')
                _emit_platform_block(emit, config, default_platform.id, ic, "            ")
                emit('        end')
            elseif #arch_platforms >= 2 then
                -- 複数 arch: windows-x86 と windows-x86_64 のケース
                emit('%sis_host("%s") then', prefix, host)
                local first_arch = true
                for _, ap in ipairs(arch_platforms) do
                    if first_arch then
                        emit('        if %s then', ap.arch_check)
                        first_arch = false
                    else
                        emit('        elseif %s then', ap.arch_check)
                    end
                    _emit_platform_block(emit, config, ap.id, ic, "            ")
                end
                if default_platform then
                    emit('        else')
                    _emit_platform_block(emit, config, default_platform.id, ic, "            ")
                end
                emit('        end')
            end
        else
            -- arch 分岐なし (単一プラットフォーム)
            local prefix = (groups[1] == group) and "    if " or "    elseif "
            emit('%sis_host("%s") then', prefix, host)
            if default_platform then
                _emit_platform_block(emit, config, default_platform.id, ic, "        ")
            end
        end
    end

    if #groups > 0 then
        emit('    end')
    end

    -- ── install テンプレート部分 ──
    local template = load_template(config.install)
    local template_code = template.generate(pkg_name, config)
    if template_code and #template_code > 0 then
        emit('')
        for _, line in ipairs(template_code) do
            emit('%s', line)
        end
    end

    emit('')
    return table.concat(lines, "\n")
end

---------------------------------------------------------------
-- _emit_platform_block: URL + versions をソースグループ単位で出力
-- source_overrides 対応: 同一プラットフォーム内でソースが変わる場合、
-- ソースごとに add_urls() + add_versions() ブロックを出力する。
---------------------------------------------------------------
function _emit_platform_block(emit, config, platform_id, ic, indent)
    indent = indent or "        "
    local has_version_map = config.version_map ~= nil
    local hash_policy = ic and ic.hash_policy

    import("provider")
    local source_groups = provider.group_versions_by_source(config)

    local first_source = true
    for _, sg in ipairs(source_groups) do
        local src = sg.source
        local versions = sg.versions

        -- このソースがこのプラットフォームにアセットを持つかチェック
        local url, fallback_url = build_xmake_url_for_source(src, platform_id)
        if url then
            -- ソースグループ間にコメント行で区切り (複数ソースの場合)
            if not first_source then
                emit('%s-- legacy source', indent)
            end
            first_source = false

            if has_version_map then
                if fallback_url then
                    emit('%sadd_urls("%s",', indent, url)
                    emit('%s         "%s", {version = function (version)', indent, fallback_url)
                else
                    emit('%sadd_urls("%s", {version = function (version)', indent, url)
                end
                emit('%s    return version_map[tostring(version)]', indent)
                emit('%send})', indent)
            else
                if fallback_url then
                    emit('%sadd_urls("%s",', indent, url)
                    emit('%s         "%s")', indent, fallback_url)
                else
                    emit('%sadd_urls("%s")', indent, url)
                end
            end

            -- このソースグループのバージョンのみ出力
            for _, version in ipairs(versions) do
                if not is_excluded(config, version, platform_id) then
                    local hash = "dummy"
                    if hash_policy ~= "dummy" and config.hashes and config.hashes[version] then
                        hash = config.hashes[version][platform_id] or "dummy"
                    end
                    emit('%sadd_versions("%s", "%s")', indent, version, hash)
                end
            end
        end
    end
end

---------------------------------------------------------------
-- generate_to_file: 生成結果をファイルに書き出す
---------------------------------------------------------------
function generate_to_file(pkg_name, config, output_path)
    local content = generate(pkg_name, config)
    io.writefile(output_path, content .. "\n")
    return content
end
