-- plugins/phc/modules/checker.lua
--
-- リンク切れ検知 + 新バージョン検知。
-- Provider をファクトリ経由でインスタンス化する。
-- Provider の登録は provider.auto_discover() が動的に行う。
-- xmake import() は非ローカル関数をエクスポートする。

local provider_mod = import("provider")

---------------------------------------------------------------
-- check_links: 全 URL の有効性を検証
---------------------------------------------------------------
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

---------------------------------------------------------------
-- check_updates: 上流の新バージョンを検知
---------------------------------------------------------------
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

        local current_latest = config.versions[1]  -- 先頭が最新
        local entry = {
            package        = pkg_name,
            current_latest = current_latest,
            new_versions   = {},
            new_tags       = {},
            source         = provider.describe_source(),
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
