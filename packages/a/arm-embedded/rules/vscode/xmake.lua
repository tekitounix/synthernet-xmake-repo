--!ARM Embedded VSCode Integration Rule
--
-- Project-level VSCode configuration generator.
-- Generates settings.json, tasks.json, and launch.json with:
--   - clangd query-driver for cross-compilers
--   - Build/Clean/Flash tasks for default target
--   - Debug configurations: OpenOCD, RTT (OpenOCD), pyOCD, Renode (if supported)
--
-- All MCU-specific data is resolved from mcu-database.json.
-- User-defined entries in tasks/launch are preserved across regeneration.

rule("embedded.vscode")
    set_kind("project")
    after_build(function (opt)

        import("core.project.config")
        import("core.project.depend")
        import("core.project.project")
        import("modules.settings_generator", { alias = "settings" })
        import("modules.tasks_generator",    { alias = "tasks" })
        import("modules.launch_generator",   { alias = "launch" })
        import("modules.mcu_info")

        -- Skip during xmake package installation
        if os.getenv("XMAKE_IN_XREPO") then
            return
        end

        -- Run only once per build (lock-based single execution)
        local tmpfile = path.join(config.builddir(), ".gens", "rules", "embedded.vscode")
        local dependfile = tmpfile .. ".d"
        local lockfile = io.openlock(tmpfile .. ".lock")
        if not lockfile:trylock() then
            return
        end

        -- Scan all targets for embedded ARM targets
        local outputdir
        local rtt_opts
        local embedded_targets = {}

        for _, target in pairs(project.targets()) do
            local toolchain = nil
            local mcu = nil

            -- Check if target uses embedded rule
            if target:rule("embedded") then
                mcu = target:values("embedded.mcu")
                toolchain = target:values("embedded.toolchain")
            end

            -- Detect ARM cross-compiler from compiler path
            local compiler = target:compiler("cxx") or target:compiler("cc")
            if compiler then
                local compiler_path = compiler:program()
                if compiler_path then
                    if compiler_path:find("arm%-none%-eabi") then
                        toolchain = toolchain or "gcc-arm"
                    elseif compiler_path:find("clang") and target:get("arch") == "arm" then
                        toolchain = toolchain or "clang-arm"
                    end
                end
            end

            -- Collect target info
            if toolchain then
                local compiler_path = compiler and compiler:program() or nil
                local probe = target:values("embedded.probe")
                if type(probe) == "table" and #probe > 0 then probe = probe[1] end
                local openocd_target_override = target:values("embedded.openocd_target")
                if type(openocd_target_override) == "table" and #openocd_target_override > 0 then
                    openocd_target_override = openocd_target_override[1]
                end
                table.insert(embedded_targets, {
                    name = target:name(),
                    mcu = mcu,
                    toolchain = toolchain,
                    compiler_path = compiler_path,
                    probe = probe,
                    openocd_target = openocd_target_override,
                })
            end

            -- Get extraconf options (outputdir, rtt, etc.)
            local extraconf = target:extraconf("rules", "embedded.vscode")
            if extraconf then
                outputdir = extraconf.outputdir
                rtt_opts = extraconf.rtt
            end
        end

        -- Always generate VSCode config (settings.json is useful for all projects)
        depend.on_changed(function ()

            local vscode_dir = outputdir or ".vscode"

            -- 1. settings.json (always generated)
            settings.generate(vscode_dir, embedded_targets)

            -- 2. Resolve default target (for tasks.json and launch.json)
            local default_target = nil
            local default_target_info = nil

            -- Priority 1: extraconf.target
            for _, target in pairs(project.targets()) do
                local extraconf = target:extraconf("rules", "embedded.vscode")
                if extraconf and extraconf.target then
                    for _, info in ipairs(embedded_targets) do
                        if info.name == extraconf.target then
                            default_target = extraconf.target
                            default_target_info = info
                            break
                        end
                    end
                    if not default_target then
                        print(string.format("warning: vscode target '%s' not found in embedded targets", extraconf.target))
                    end
                    break
                end
            end

            -- Priority 2: set_default(true)
            if not default_target then
                for _, info in ipairs(embedded_targets) do
                    local target = project.target(info.name)
                    if target and target:get("default") then
                        default_target = info.name
                        default_target_info = info
                        break
                    end
                end
            end

            -- Priority 3: first embedded target
            if not default_target and #embedded_targets > 0 then
                default_target = embedded_targets[1].name
                default_target_info = embedded_targets[1]
                print(string.format("warning: no default target specified, using '%s' for vscode configuration", default_target))
            end

            if not default_target then
                return
            end

            -- 3. Resolve MCU info (needed for both tasks.json and launch.json)
            local mcu_name = default_target_info.mcu
            if type(mcu_name) == "table" and #mcu_name > 0 then
                mcu_name = mcu_name[1]
            end

            local info = nil
            local renode_info = nil
            if mcu_name then
                local mcu_db_path = path.join(os.scriptdir(), "..", "embedded", "database", "mcu-database.json")
                info = mcu_info.resolve(mcu_db_path, mcu_name, {
                    probe = default_target_info.probe,
                    openocd_target = default_target_info.openocd_target,
                })

                -- Prepare Renode info if MCU supports it
                if info.renode_repl then
                    -- Resolve Renode executable path for VSCode tasks.json.
                    -- Priority: PATH (includes xmake package bin/) > macOS .app > bare command
                    import("lib.detect.find_program")
                    local renode_cmd = find_program("renode")
                    if not renode_cmd then
                        local macos_app = "/Applications/Renode.app/Contents/MacOS/Renode"
                        if os.isfile(macos_app) then
                            renode_cmd = macos_app
                        else
                            renode_cmd = "renode"
                        end
                    end
                    renode_info = {
                        resc_path = "build/" .. default_target .. "/debug/" .. default_target .. "_renode.resc",
                        renode_cmd = renode_cmd,
                    }
                end
            end

            -- 4. tasks.json
            tasks.generate(vscode_dir, default_target, renode_info)

            -- 5. launch.json
            if info then
                launch.generate(vscode_dir, default_target_info, info, rtt_opts)
            end

        end, {dependfile = dependfile,
              files = table.join(project.allfiles(), config.filepath()),
              values = embedded_targets})

        lockfile:close()
    end)
