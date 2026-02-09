-- packages/p/phc/xmake.lua
--
-- Package Health Check (PHC) — メタパッケージ定義
--
-- プラグインを ~/.xmake/plugins/phc/ にインストールし、
-- `xmake phc` コマンドを利用可能にする。
--

package("phc")
    set_kind("library")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("Package Health Check — xmake plugin for link & version monitoring")

    on_load(function (package)
        import("core.base.global")

        local src = os.scriptdir()
        local dest_root = global.directory()
        local dest_plugin = path.join(dest_root, "plugins", "phc")

        -- Helper: recursively copy all files under src_dir to dest_dir
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

        -- Clean stale files from previous versions
        if os.isdir(dest_plugin) then
            os.rmdir(dest_plugin)
        end

        -- 1. Copy plugin (xmake.lua + modules/)
        local plugin_src = path.join(src, "plugins", "phc")
        local n = sync_tree(plugin_src, dest_plugin)

        -- 2. Copy registry into plugin directory for self-contained operation
        local registry_src = path.join(src, "registry")
        local registry_dest = path.join(dest_plugin, "registry")
        n = n + sync_tree(registry_src, registry_dest)

        cprint("${green}[phc]${clear} Plugin installed (%d files) → %s", n, dest_plugin)
    end)

    on_install(function (package)
        -- メタパッケージ: on_load() で全インストールが完了している
    end)

    on_test(function (package)
        -- プラグインが正しくインストールされているか確認
        import("core.base.global")
        local phc_xmake = path.join(global.directory(), "plugins", "phc", "xmake.lua")
        assert(os.isfile(phc_xmake), "phc plugin not installed")
    end)
package_end()
