-- Flash task for ARM embedded targets using PyOCD

task("flash")
    set_category("plugin")
    set_menu {
        usage = "xmake flash [options] [target]",
        description = "Flash ARM embedded target using PyOCD",
        options = {
            {'t', "target", "kv", nil, "Specify target to flash"},
            {'d', "device", "kv", nil, "Override target device (e.g., stm32f407vg)"},
            {'f', "frequency", "kv", nil, "Set SWD clock frequency (e.g., 1M, 4M)"},
            {'e', "erase", "k", nil, "Perform chip erase before programming"},
            {'r', "reset", "k", nil, "Reset target after programming"},
            {'n', "no-reset", "k", nil, "Do not reset target after programming"},
            {'p', "probe", "kv", nil, "Specify debug probe to use"},
            {nil, "connect", "kv", nil, "Connection mode (halt, pre-reset, under-reset)"},
            {'y', "yes", "k", nil, "Auto-confirm prompts (for CI/CD, non-interactive mode)"}
        }
    }
    
    on_run(function()
        import("core.base.option")
        import("core.project.project")
        import("core.project.target")
        import("core.project.config")
        
        -- Load project configuration
        config.load()
        
        -- Get target
        local targetname = option.get("target")
        local target_obj = nil
        
        if targetname then
            target_obj = project.target(targetname)
            if not target_obj then
                raise("Target not found: " .. targetname)
            end
        else
            -- Try to find default target first
            -- Sort target names for consistent behavior
            local target_names = {}
            for name, _ in pairs(project.targets()) do
                table.insert(target_names, name)
            end
            table.sort(target_names)
            
            -- Find the target that was explicitly set as default in xmake.lua
            local default_targets = {}
            for _, name in ipairs(target_names) do
                local target = project.target(name)
                -- Check if the target has default property explicitly set to true
                if target:get("default") == true and target:rule("embedded") then
                    table.insert(default_targets, {name = name, target = target})
                end
            end
            
            -- If multiple defaults found, use the first one alphabetically
            if #default_targets > 0 then
                if #default_targets > 1 then
                    local names = {}
                    for _, t in ipairs(default_targets) do
                        table.insert(names, t.name)
                    end
                    print(string.format("Warning: Multiple default targets found: %s", 
                        table.concat(names, ", ")))
                    print("Using first target alphabetically: " .. default_targets[1].name)
                end
                target_obj = default_targets[1].target
            end
            
            -- If no default, find first embedded target
            if not target_obj then
                for _, target in pairs(project.targets()) do
                    if target:rule("embedded") then
                        target_obj = target
                        break
                    end
                end
            end
            
            if not target_obj then
                raise("No embedded target found. Please specify a target.")
            end
        end
        
        -- Show which target is being used
        print("=> Using target: %s", target_obj:name())
        
        -- Get target file (ELF) first to check if it exists
        local targetfile = target_obj:targetfile()
        
        -- Build only if target file doesn't exist
        if not targetfile or not os.isfile(targetfile) then
            print("=> Building target: %s", target_obj:name())
            os.execv("xmake", {"build", target_obj:name()})
        else
            -- Check if we need to rebuild by comparing timestamps
            local sourcefiles = target_obj:sourcefiles()
            local need_rebuild = false
            
            for _, sourcefile in ipairs(sourcefiles) do
                if os.mtime(sourcefile) > os.mtime(targetfile) then
                    need_rebuild = true
                    break
                end
            end
            
            if need_rebuild then
                print("=> Rebuilding target: %s (source files changed)", target_obj:name())
                os.execv("xmake", {"build", target_obj:name()})
            else
                print("=> Target is up-to-date: %s", target_obj:name())
            end
        end
        
        -- Get target file (ELF)
        local targetfile = target_obj:targetfile()
        if not targetfile or not os.isfile(targetfile) then
            raise("Target ELF file not found. Make sure the target was built successfully.")
        end
        
        -- Load flash targets configuration
        import("core.base.json")
        import("core.base.global")
        local plugin_dir = path.join(global.directory(), "plugins", "flash")
        local database_dir = path.join(plugin_dir, "database")
        local flash_config = json.loadfile(path.join(database_dir, "flash-targets.json"))
        if not flash_config then
            raise("Failed to load flash plugin database/flash-targets.json")
        end
        
        -- Get device
        local device = option.get("device") or target_obj:data("embedded.mcu")
        if not device then
            raise([[
No target device specified. Please specify the device using one of:

1. In your xmake.lua:
   set_values("embedded.mcu", "stm32f407vg")

2. Via command line:
   $ xmake flash -d stm32f407vg

For a full list of supported targets, run:
$ pyocd list --targets
]])
        end
        
        -- Check for target aliases
        local original_device = device
        if flash_config.FLASH_TARGETS.target_aliases.aliases[device] then
            device = flash_config.FLASH_TARGETS.target_aliases.aliases[device]
            print("=> Using target alias: %s -> %s", original_device, device)
        end
        
        -- Check if pyocd is available (prioritize package version)
        local pyocd = nil
        
        -- First, try to use pyocd from package
        local pyocd_path = path.join(global.directory(), "packages", "p", "pyocd")
        if os.isdir(pyocd_path) then
            local versions = os.dirs(path.join(pyocd_path, "*"))
            if #versions > 0 then
                table.sort(versions)
                local latest = versions[#versions]
                local installs = os.dirs(path.join(latest, "*"))
                if #installs > 0 then
                    local install_dir = installs[1]
                    local pyocd_bin = path.join(install_dir, "bin", "pyocd")
                    if is_host("windows") then
                        pyocd_bin = pyocd_bin .. ".bat"
                    end
                    if os.isfile(pyocd_bin) then
                        -- Verify PyOCD is actually executable
                        local ok = try { function()
                            os.vrunv(pyocd_bin, {"--version"}, {curdir = os.projectdir()})
                            return true
                        end }
                        
                        if ok then
                            pyocd = {program = pyocd_bin}
                            print("Using PyOCD from package: " .. pyocd_bin)
                        else
                            print("warning: PyOCD found but not functional at: " .. pyocd_bin)
                            print("warning: This may indicate PyOCD needs to be reinstalled")
                        end
                    end
                end
            end
        end
        
        -- Fallback to system pyocd
        if not pyocd then
            import("lib.detect.find_tool")
            pyocd = find_tool("pyocd")
            if pyocd then
                print("Using system PyOCD: " .. pyocd.program)
            end
        end
        
        if not pyocd then
            raise([[
error: PyOCD not found or not functional

PyOCD is required to flash ARM embedded targets but was not found or is not working properly.

Please install/reinstall PyOCD using one of the following methods:

1. Install via xmake (recommended):
   $ xmake require --force pyocd

2. Install via pip:
   $ pip install --upgrade pyocd==0.34.2

3. Install via your package manager:
   - macOS: brew install pyocd
   - Ubuntu: apt install python3-pyocd

If PyOCD was previously installed but is not working:
   $ xmake require --force -y pyocd python3

Note: The flash task requires PyOCD to communicate with the target device.
Make sure your debug probe is connected and drivers are installed.
]])
        end
        
        -- Check if device pack is required and handle auto-installation
        local function check_and_install_pack()
            local pack_targets = flash_config.FLASH_TARGETS.pack_required.targets
            local target_info = pack_targets[device]
            
            if target_info and target_info.auto_install_pack then
                print("=> Checking device pack for %s...", device)
                
                -- Check if pack is already installed
                local pack_list_output = os.iorunv(pyocd.program, {"pack", "show"})
                local pack_installed = false
                
                if pack_list_output then
                    -- Check for pack name in various formats (e.g., Keil.STM32F4xx_DFP)
                    local pack_pattern = target_info.pack_name:upper()
                    pack_installed = pack_list_output:upper():find(pack_pattern) ~= nil or
                                   pack_list_output:upper():find("STM32" .. pack_pattern:sub(6) .. "XX_DFP") ~= nil
                end
                
                if not pack_installed then
                    print("=> Device pack '%s' not installed", target_info.pack_name)

                    if flash_config.PACK_MANAGEMENT.auto_install_enabled then
                        local auto_confirm = option.get("yes")
                        local do_install = auto_confirm

                        if not auto_confirm then
                            -- Check if we're in a non-interactive environment (CI/CD)
                            local is_interactive = os.getenv("CI") == nil and os.getenv("GITHUB_ACTIONS") == nil
                            if is_interactive then
                                io.write("Would you like to install the required device pack automatically? [Y/n]: ")
                                io.flush()
                                local input = io.read()
                                do_install = input == "" or input:lower() == "y" or input:lower() == "yes"
                            else
                                -- Non-interactive mode without --yes flag: skip pack installation
                                print("=> Skipping pack installation in non-interactive mode")
                                print("   Use --yes (-y) to auto-install, or manually run:")
                                print("   %s", target_info.pack_install_command)
                                do_install = false
                            end
                        end

                        if do_install then
                            print("=> Installing device pack: %s", target_info.pack_name)

                            local pack_install_args = {"pack", "--install", target_info.pack_name}
                            local pack_ok = os.execv(pyocd.program, pack_install_args)

                            if pack_ok then
                                print("=> Device pack installed successfully")
                            else
                                raise("Failed to install device pack: " .. target_info.pack_name)
                            end
                        else
                            print("=> Continuing without pack installation")
                            print("   Manual installation: %s", target_info.pack_install_command)
                        end
                    else
                        print("=> Auto-installation disabled")
                        print("   Manual installation: %s", target_info.pack_install_command)
                    end
                else
                    print("=> Device pack '%s' already installed", target_info.pack_name)
                end
            end
        end
        
        -- Check and install pack if needed
        check_and_install_pack()
        
        -- Build pyocd command
        local argv = {"flash", "-t", device, "--format", "elf"}
        
        -- Add optional arguments
        if option.get("frequency") then
            table.insert(argv, "-f")
            table.insert(argv, option.get("frequency"))
        end
        
        if option.get("erase") then
            table.insert(argv, "-e")
            table.insert(argv, "chip")
        end
        
        -- Check for probe specification (command line takes priority)
        local probe = option.get("probe") or target_obj:values("embedded.probe")
        if type(probe) == "table" and #probe > 0 then
            probe = probe[1]  -- Take first value if array
        end
        
        if probe then
            table.insert(argv, "--probe")
            table.insert(argv, probe)
            print("=> Using probe: %s", probe)
        else
            -- No probe specified, PyOCD will show available probes for selection
            print("=> No probe specified, PyOCD will show available probes")
        end
        
        if option.get("connect") then
            table.insert(argv, "--connect")
            table.insert(argv, option.get("connect"))
        end
        
        -- Add ELF file
        table.insert(argv, targetfile)
        
        -- Reset behavior
        if option.get("no-reset") then
            table.insert(argv, "--no-reset")
        elseif option.get("reset") then
            table.insert(argv, "--reset-type")
            table.insert(argv, "hw")
        end
        
        -- Get file size for progress indication
        local filesize = os.filesize(targetfile)
        local filesize_kb = math.floor(filesize / 1024)
        
        -- Execute pyocd
        print("=> Flashing %s (%d KB) to %s", path.filename(targetfile), filesize_kb, device)
        
        -- Add verbose flag for progress output
        table.insert(argv, "--verbose")
        
        -- Execute with output capture for progress parsing
        local outdata = {}
        local errdata = {}
        local ok = os.execv(pyocd.program, argv, {stdout = function(line)
            -- Skip probe list output from PyOCD completely
            if line:find("^%s*#%s+Probe/Board") or line:find("^%-%-%-") or 
               line:find("^%s*%d+%s+%S") or line:find("Enter the number") or
               line:find("DISCO%-") or line:find("STLINK%-") or line:find("STM32 STLink") or
               line:find("^%s*$") then  -- Skip empty lines from probe list
                return
            end
            
            -- Parse PyOCD output for progress information
            if line:find("Erased %d+ bytes") or line:find("programmed %d+ bytes") or line:find("skipped %d+ bytes") then
                -- Clean progress line
                local progress_info = line:gsub("^%d+ [A-Z] ", "")
                print("   " .. progress_info)
            elseif line:find("^%[") then
                -- Progress bar
                io.write("\r" .. line)
                io.flush()
            end
            table.insert(outdata, line)
        end, stderr = function(line)
            table.insert(errdata, line)
        end})
        
        -- Clear progress bar line
        io.write("\r" .. string.rep(" ", 80) .. "\r")
        io.flush()
        
        local exitcode = ok and 0 or 1
        
        if exitcode ~= 0 then
            -- Check if user cancelled probe selection
            local user_cancelled = false
            if #errdata > 0 then
                for _, line in ipairs(errdata) do
                    if line:find("No target device available") then
                        user_cancelled = true
                        break
                    end
                end
            end
            
            if user_cancelled then
                print("")
                print("=> Flash operation cancelled by user")
                print("")
                print("To flash without probe selection, use:")
                print("  $ xmake flash -t " .. target_obj:name() .. " -p <probe_uid>")
                print("")
                print("Run 'xmake flash --list' to see available probe UIDs.")
                os.exit(0)  -- Exit cleanly for user cancellation
            else
                print("")
                print("Error: Flash operation failed (exit code: " .. tostring(exitcode) .. ")")
                print("")
                print("Troubleshooting:")
                print("1. Check debug probe connection")
                print("2. Verify target power supply")
                print("3. Try different USB port/cable")
                print("4. Update probe firmware if needed")
                print("5. Run with elevated privileges if necessary")
                print("6. If multiple probes connected, use: xmake flash --probe <unique_id>")
                print("")
                
                -- Show captured error output if available
                if #errdata > 0 then
                    print("Error details:")
                    for _, line in ipairs(errdata) do
                        print("  " .. line)
                    end
                    print("")
                end
                
                print("For more verbose output, run:")
                print("  $ pyocd flash --verbose --format elf " .. targetfile)
                os.exit(1)
            end
        else
            print("=> Flash completed successfully")
        end
    end)