-- plugins/phc/modules/validator.lua
--
-- registry (packages.lua) ↔ xmake.lua の整合性検証。
-- バージョン一致と URL パターンの軽量チェックを行う。
-- xmake import() は非ローカル関数をエクスポートする。

function validate(registry, packages_dir)
    local issues = {}

    for _, pkg_name in ipairs(registry.package_names()) do
        local config = registry.package_config(pkg_name)

        -- xmake.lua 探索: packages/<first_letter>/<name>/xmake.lua
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

        -- URL パターン整合性（軽量チェック）
        _check_urls(pkg_name, config, content, issues)

        ::continue::
    end

    return issues
end

function _check_urls(pkg_name, config, content, issues)
    -- デフォルトソース + source_overrides のすべてのソースを検証
    local sources_to_check = {}

    local ptype = config.type
    if ptype == "github-release" then
        table.insert(sources_to_check, {type = "github-release", repo = config.repo})
    elseif ptype == "http-direct" then
        table.insert(sources_to_check, {type = "http-direct", base_url = config.base_url})
    end

    if config.source_overrides then
        for _, override in ipairs(config.source_overrides) do
            if override.repo then
                table.insert(sources_to_check, {type = "github-release", repo = override.repo})
            end
            if override.base_url then
                table.insert(sources_to_check, {type = "http-direct", base_url = override.base_url})
            end
        end
    end

    for _, src in ipairs(sources_to_check) do
        if src.type == "github-release" then
            local expected = ("github.com/%s/releases"):format(src.repo)
            if not content:find(expected, 1, true) then
                table.insert(issues, {
                    package  = pkg_name,
                    severity = "warning",
                    message  = ("expected URL containing '%s' not found in xmake.lua"):format(expected),
                })
            end
        elseif src.type == "http-direct" then
            local base = src.base_url or ""
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
end
