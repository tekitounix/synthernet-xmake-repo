-- plugins/phc/modules/provider_http.lua
--
-- HTTP Direct Provider
-- CDN 等の直リンクでアセットを取得するパッケージ用。
-- HEAD/GET でリンク存在確認。新バージョン検知は update_check 設定で別 Provider に委譲。
-- xmake サンドボックスでは setmetatable 不可のため closure ベース。

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
    self.update_check = config.update_check  -- optional: {type, repo, tag_pattern}

    function self.describe_source()
        local uc = self.update_check
        if uc and uc.repo then
            return "http-direct (via github:" .. uc.repo .. ")"
        end
        return "http-direct"
    end

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
        -- HEAD を試す（CDN によっては HEAD を拒否するため GET にフォールバック）
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
        -- CDN にはバージョン一覧 API がないため、update_check で指定された
        -- 別の Provider を使って検知する
        if not self.update_check then return {} end

        local uc = self.update_check
        if uc.type == "github-release" then
            -- GitHubRelease Provider を一時的に生成して discover_versions() を委譲
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

-- xmake import() は非ローカル関数をエクスポートする (return 不要)
