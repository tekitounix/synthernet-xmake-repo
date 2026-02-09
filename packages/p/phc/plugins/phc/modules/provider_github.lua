-- plugins/phc/modules/provider_github.lua
--
-- GitHub Releases Provider
-- リリースアセットの存在確認と新バージョン検知を GitHub API 経由で行う。
-- xmake サンドボックスでは setmetatable 不可のため closure ベース。

local provider_mod = import("provider")

--- GitHub API GET via curl
-- xmake の net.http は REST API 向けに限定的なため curl を使用
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

    -- 最終行が HTTP ステータスコード
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

    function self.describe_source()
        return "github:" .. (self.repo or "?")
    end

    local function format_tag(version)
        return self.expand(self.tag_pattern, version)
    end

    function self.resolve_urls()
        local results = {}
        for _, version in ipairs(self.versions) do
            local src = provider_mod.resolve_source(self.config, version)
            local tag = self.expand(src.tag_pattern, version)
            local assets = src.assets or self.assets
            for platform, template in pairs(assets) do
                if not self.is_excluded(version, platform) then
                    local asset_name = self.expand(template, version)
                    local url = ("https://github.com/%s/releases/download/%s/%s"):format(
                        src.repo, tag, asset_name)
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
        local src = provider_mod.resolve_source(self.config, asset.version)
        local assets = src.assets or self.assets
        local tag = self.expand(src.tag_pattern, asset.version)
        local expected = self.expand(assets[asset.platform], asset.version)
        local api_url = ("https://api.github.com/repos/%s/releases/tags/%s"):format(src.repo, tag)

        local ok, body, status = api_get(api_url)

        -- primary tag が 404 の場合、fallback tag を試す
        if not ok and src.fallback_tag_pattern then
            local fallback_tag = self.expand(src.fallback_tag_pattern, asset.version)
            local fallback_url = ("https://api.github.com/repos/%s/releases/tags/%s"):format(
                src.repo, fallback_tag)
            ok, body, status = api_get(fallback_url)
        end

        if not ok then
            return {asset = asset, status = "fail", http_status = status, error = body}
        end

        -- JSON パースしてアセット名を確認
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
        local known = {}
        for _, v in ipairs(self.versions) do known[v] = true end

        -- 検出対象ソースを収集: discover_from = true のオーバーライド、
        -- またはオーバーライドがなければデフォルトソース
        local discover_sources = {}
        local has_discover_from = false
        if self.config.source_overrides then
            for _, override in ipairs(self.config.source_overrides) do
                if override.discover_from then
                    has_discover_from = true
                    table.insert(discover_sources, {
                        repo = override.repo or self.repo,
                        tag_pattern = override.tag_pattern or self.tag_pattern,
                    })
                end
            end
        end
        -- discover_from 指定がなければデフォルトリポジトリから検出
        if not has_discover_from then
            table.insert(discover_sources, {
                repo = self.repo,
                tag_pattern = self.tag_pattern,
            })
        end

        local results = {}
        local seen = {}
        for _, ds in ipairs(discover_sources) do
            local api_url = ("https://api.github.com/repos/%s/releases?per_page=50"):format(ds.repo)
            local ok, body, status = api_get(api_url)
            if ok then
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
                if json_ok and type(releases) == "table" then
                    local escaped = ds.tag_pattern:gsub("([%.%+%-%*%?%[%]%^%$%(%)%%])", "%%%1")
                    local lua_pattern = "^" .. escaped:gsub("%%%%%%%%%(version%)", "(.+)") .. "$"

                    for _, release in ipairs(releases) do
                        if not release.draft and (self.include_prerelease or not release.prerelease) then
                            local tag = release.tag_name
                            local version = tag:match(lua_pattern)
                            if version and not seen[version] then
                                seen[version] = true
                                table.insert(results, {
                                    version = version,
                                    tag     = tag,
                                    is_new  = not known[version],
                                    source  = ds.repo,
                                })
                            end
                        end
                    end
                end
            end
        end
        return results
    end

    return self
end

-- ファクトリに登録
provider_mod.register("github-release", new)

-- xmake import() は非ローカル関数をエクスポートする (return 不要)
