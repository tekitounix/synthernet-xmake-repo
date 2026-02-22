package("arm-embedded")
    set_kind("library")
    set_description("ARM embedded development environment with toolchains, rules, and flashing support")
    set_homepage("https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm")
    
    -- Dependencies (let user choose specific versions)
    add_deps("clang-arm")
    add_deps("gcc-arm")
    -- Python3 and PyOCD are optional dependencies for flash functionality
    -- Users can install them separately if needed: xmake require python3 pyocd
    
    -- Development version
    add_versions("0.1.0-dev", "dummy")
    add_versions("0.1.1", "dummy")
    add_versions("0.1.2", "dummy")
    add_versions("0.1.3", "dummy")
    add_versions("0.1.4", "dummy")
    add_versions("0.1.5", "dummy")
    add_versions("0.1.6", "dummy")
    add_versions("0.1.7", "dummy")
    add_versions("0.1.8", "dummy")
    add_versions("0.1.9", "dummy")
    add_versions("0.1.10", "dummy")
    add_versions("0.2.0", "dummy")
    
    
    on_load(function (package)
        -- Install rule and task definitions to user's xmake directory.
        -- Always overwrite to ensure package source is the single source of truth.
        -- This guarantees `xmake require --force` cleanly updates all installed files.
        --
        -- Dynamic scan: walks source directories so new files are automatically included.
        import("core.base.global")

        local src = os.scriptdir()
        local dest_root = global.directory()

        -- Source rule name → installed rule name mapping
        -- (only entries that differ need to be listed)
        local rule_name_map = {
            vscode = "embedded.vscode",
            compdb = "embedded.compdb"
        }

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

        -- 0. Remove known legacy directories from previous versions.
        -- These were removed or consolidated in the current package structure.
        -- Keep this list until all developer environments have been updated.
        local legacy = {
            rules  = {"embedded.debugger", "umibm.firmware", "umios.firmware"},   -- merged into generic firmware rule
            plugins = {"debug", "debugger", "deploy", "emulator", "project", "serve"}  -- unused/redundant
        }
        for _, name in ipairs(legacy.rules) do
            local d = path.join(dest_root, "rules", name)
            if os.isdir(d) then os.rmdir(d) end
        end
        for _, name in ipairs(legacy.plugins) do
            local d = path.join(dest_root, "plugins", name)
            if os.isdir(d) then os.rmdir(d) end
        end

        -- 1. Rules: clean destination then copy from source
        local rules_src = path.join(src, "rules")
        if os.isdir(rules_src) then
            for _, dir in ipairs(os.dirs(path.join(rules_src, "*"))) do
                local rule_name = path.filename(dir)
                local dest_name = rule_name_map[rule_name] or rule_name
                local dest_dir = path.join(dest_root, "rules", dest_name)
                -- Remove stale files from previous versions before copying
                if os.isdir(dest_dir) then
                    os.rmdir(dest_dir)
                end
                sync_tree(dir, dest_dir)
            end
        end

        -- 2. Plugins: clean destination then copy from source
        local plugins_src = path.join(src, "plugins")
        if os.isdir(plugins_src) then
            for _, dir in ipairs(os.dirs(path.join(plugins_src, "*"))) do
                local plugin_name = path.filename(dir)
                local dest_dir = path.join(dest_root, "plugins", plugin_name)
                -- Remove stale files from previous versions before copying
                if os.isdir(dest_dir) then
                    os.rmdir(dest_dir)
                end
                sync_tree(dir, dest_dir)
            end
        end

        -- 3. Claude staging: claude/ → ~/.xmake/rules/embedded/claude/
        local claude_src = path.join(src, "claude")
        if os.isdir(claude_src) then
            local claude_dest = path.join(dest_root, "rules", "embedded", "claude")
            sync_tree(claude_src, claude_dest)
        end

        -- 4. Scripts: scripts/ → ~/.xmake/rules/embedded/scripts/
        local scripts_src = path.join(src, "scripts")
        if os.isdir(scripts_src) then
            local scripts_dest = path.join(dest_root, "rules", "embedded", "scripts")
            sync_tree(scripts_src, scripts_dest)
        end
    end)
    
    on_install(function (package)
        -- Linker scripts are now part of the embedded rule
        -- No separate installation needed
        -- The actual installation happens in on_load to ensure rules are available early
        
        -- Verify that all required files were installed
        import("core.base.global")
        
        -- Check embedded rule
        local embedded_rule = path.join(global.directory(), "rules", "embedded", "xmake.lua")
        if not os.isfile(embedded_rule) then
            raise("Embedded rule not installed correctly")
        end
        
        -- Check flash task
        local flash_task = path.join(global.directory(), "plugins", "flash", "xmake.lua")
        if not os.isfile(flash_task) then
            raise("Flash task not installed correctly")
        end
        
        print("ARM Embedded package installed successfully")
    end)
    
    
    on_test(function (package)
        -- Test if dependencies are available and functional
        local clang = package:dep("clang-arm")
        local pyocd = package:dep("pyocd")
        
        -- Test if embedded rule was properly installed
        import("core.base.global")
        local embedded_rule = path.join(global.directory(), "rules", "embedded", "xmake.lua")
        assert(os.isfile(embedded_rule), "Embedded rule not found")
        
        -- Test if flash task was properly installed
        local flash_task = path.join(global.directory(), "plugins", "flash", "xmake.lua")
        assert(os.isfile(flash_task), "Flash task not found")
        
        -- Test if database files were properly installed
        local mcu_db = path.join(global.directory(), "rules", "embedded", "database", "mcu-database.json")
        assert(os.isfile(mcu_db), "MCU database not found")
        
        -- Test if linker script was properly installed
        local linker_script = path.join(global.directory(), "rules", "embedded", "linker", "common.ld")
        assert(os.isfile(linker_script), "Linker script not found")
        
        -- Test dependency functionality if available
        if clang then
            local clang_bin = path.join(clang:installdir(), "bin", "clang")
            if clang:is_plat("windows") then
                clang_bin = clang_bin .. ".exe"
            end
            if os.isfile(clang_bin) then
                local ok = try { function()
                    os.vrunv(clang_bin, {"--version"})
                    return true
                end }
                if ok then
                    print("Clang ARM: OK")
                end
            end
        end
        
        if pyocd then
            local pyocd_bin = path.join(pyocd:installdir(), "bin", "pyocd")
            if pyocd:is_plat("windows") then
                pyocd_bin = pyocd_bin .. ".bat"
            end
            if os.isfile(pyocd_bin) then
                local ok = try { function()
                    os.vrunv(pyocd_bin, {"--version"})
                    return true
                end }
                if ok then
                    print("PyOCD: OK")
                end
            end
        end
        
        print("ARM Embedded environment: OK")
    end)

