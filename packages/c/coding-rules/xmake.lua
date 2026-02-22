package("coding-rules")
    set_kind("library")
    set_description("C++ coding style and testing automation for embedded development")

    -- Version management
    add_versions("0.1.0", "dummy")
    add_versions("0.1.1", "dummy")
    add_versions("0.1.2", "dummy")
    add_versions("0.1.3", "dummy")
    add_versions("0.1.4", "dummy")
    add_versions("0.2.0", "dummy")

    on_load(function (package)
        -- Install rules, plugins, and Claude staging files to ~/.xmake/
        -- Config files (.clang-format, .clang-tidy, .clangd) are NOT distributed
        -- to project root. Project root files are the single source of truth.
        import("core.base.global")

        local src = os.scriptdir()
        local dest_root = global.directory()

        -- Helper: recursively copy with timestamp comparison
        local function sync_tree(src_dir, dest_dir)
            if not os.isdir(src_dir) then return 0 end
            local count = 0
            for _, f in ipairs(os.files(path.join(src_dir, "**"))) do
                local rel = path.relative(f, src_dir)
                local dest_file = path.join(dest_dir, rel)
                if not os.isfile(dest_file) or os.mtime(f) > os.mtime(dest_file) then
                    os.mkdir(path.directory(dest_file))
                    io.writefile(dest_file, io.readfile(f))
                    count = count + 1
                end
            end
            return count
        end

        local coding_rule_dest = path.join(dest_root, "rules", "coding")

        -- 1. Coding rule xmake.lua → ~/.xmake/rules/coding/
        local rule_file = path.join(src, "rules", "coding", "xmake.lua")
        if os.isfile(rule_file) then
            local dest_file = path.join(coding_rule_dest, "xmake.lua")
            local content = io.readfile(rule_file)
            local need_update = not os.isfile(dest_file) or io.readfile(dest_file) ~= content
            if need_update then
                os.mkdir(coding_rule_dest)
                io.writefile(dest_file, content)
            end
        end

        -- Config templates (for `xmake coding init` only, not deployed to project)
        sync_tree(path.join(src, "rules", "coding", "configs"),
                  path.join(coding_rule_dest, "configs"))

        -- 2. Testing rule → ~/.xmake/rules/testing/
        sync_tree(path.join(src, "rules", "testing"),
                  path.join(dest_root, "rules", "testing"))

        -- 3. Plugins → ~/.xmake/plugins/
        local plugins_src = path.join(src, "plugins")
        if os.isdir(plugins_src) then
            for _, dir in ipairs(os.dirs(path.join(plugins_src, "*"))) do
                local plugin_name = path.filename(dir)
                sync_tree(dir, path.join(dest_root, "plugins", plugin_name))
            end
        end

        -- 4. Claude files → ~/.xmake/rules/coding/claude/ (staging area)
        sync_tree(path.join(src, "claude"),
                  path.join(coding_rule_dest, "claude"))

        -- 5. Shared scripts → ~/.xmake/rules/coding/scripts/
        sync_tree(path.join(src, "scripts"),
                  path.join(coding_rule_dest, "scripts"))
    end)

    on_install(function (package)
        import("core.base.global")

        local coding_rule = path.join(global.directory(), "rules", "coding", "xmake.lua")
        if not os.isfile(coding_rule) then
            raise("Coding rule not installed correctly")
        end

        local testing_rule = path.join(global.directory(), "rules", "testing", "xmake.lua")
        if not os.isfile(testing_rule) then
            raise("Testing rule not installed correctly")
        end

        print("Coding rules package installed successfully")
    end)

    on_test(function (package)
        import("core.base.global")
        assert(os.isfile(path.join(global.directory(), "rules", "coding", "xmake.lua")),
               "Coding rule not found")
        assert(os.isfile(path.join(global.directory(), "rules", "testing", "xmake.lua")),
               "Testing rule not found")
        print("Coding rules environment: OK")
    end)