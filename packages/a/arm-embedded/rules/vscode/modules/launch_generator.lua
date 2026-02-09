-- Launch.json generator for VSCode Cortex-Debug configurations.
-- Generates OpenOCD, RTT, pyOCD, and Renode debug configurations for the default target,
-- with MCU-specific settings resolved from mcu-database.json.

import("core.base.json")
import("json_file")

-- Managed configuration names (regenerated on every build).
local managed_names = {
    ["Debug (OPENOCD)"] = true,
    ["Debug (RTT)"]     = true,
    ["Debug (PYOCD)"]   = true,
    ["Debug (RENODE)"]  = true,
}

local function is_managed(name)
    return managed_names[name] == true
end

-- Generate a Renode .resc script for GDB debug.
--
-- @param resc_path     Output path for the .resc file
-- @param repl_path     Relative path to .repl platform description
-- @param target_name   Build target name
-- @param flash_origin  Flash origin address (e.g. "0x08000000")
-- @param gdb_port      GDB server port (default 3333)
local function generate_debug_resc(resc_path, repl_path, target_name, flash_origin, gdb_port)
    gdb_port = gdb_port or 3333
    local flash_origin_plus4 = string.format("0x%08X", tonumber(flash_origin) + 4)

    local lines = {
        "# Auto-generated Renode GDB debug script",
        "# Do not edit — regenerated on every build",
        "",
        "using sysbus",
        "",
        'mach create "' .. target_name .. '"',
        "",
        "machine LoadPlatformDescription $CWD/" .. repl_path,
        "sysbus LoadELF $CWD/build/" .. target_name .. "/debug/" .. target_name .. ".elf",
        "",
        "sysbus WriteDoubleWord 0xE000ED08 " .. flash_origin,
        "sysbus WriteDoubleWord 0x00000000 `sysbus ReadDoubleWord " .. flash_origin .. "`",
        "sysbus WriteDoubleWord 0x00000004 `sysbus ReadDoubleWord " .. flash_origin_plus4 .. "`",
        "",
        "cpu PerformanceInMips 100",
        "machine StartGdbServer " .. gdb_port,
        "",
    }

    os.mkdir(path.directory(resc_path))
    io.writefile(resc_path, table.concat(lines, "\n"))
end

-- RTT defaults (umirtm library convention).
-- rtt_start_retry: CB detection may fail if firmware hasn't initialized RTM
--   yet when cortex-debug issues "rtt start".  Retry ensures detection
--   once init() completes (typically before main()).
-- polling_interval: how often OpenOCD polls the RTT buffer (ms).
-- searchSize: scan range from ram_origin.  4 KiB covers typical .bss
--   placement without risk of matching a stale control block left over
--   from a previous session.
local rtt_defaults = {
    searchId = "RT MONITOR",
    searchSize = 4096,
    rtt_start_retry = 500,
    polling_interval = 10,
}

-- Generate or update .vscode/launch.json.
--
-- @param vscode_dir          Path to .vscode directory
-- @param default_target_info Table { name, mcu, ... } for the default target
-- @param mcu_info            Table from mcu_info.resolve()
-- @param rtt_opts            Optional RTT overrides { searchId, searchSize, decoders }
function generate(vscode_dir, default_target_info, mcu_info, rtt_opts)
    rtt_opts = rtt_opts or {}
    local launch_file = path.join(vscode_dir, "launch.json")
    local target_name = default_target_info.name

    -- Load existing file, keeping only user-defined configurations
    local launch = json_file.load_and_filter(launch_file, "configurations", is_managed, "name")

    local executable = "${workspaceFolder}/build/" .. target_name .. "/debug/" .. target_name

    -- OpenOCD configuration
    local openocd_config = {
        name = "Debug (OPENOCD)",
        type = "cortex-debug",
        request = "launch",
        servertype = "openocd",
        cwd = "${workspaceFolder}",
        executable = executable,
        runToEntryPoint = "main",
        showDevDebugOutput = "none",
        preLaunchTask = "Build (Debug)",
        device = mcu_info.device_name,
        configFiles = {
            mcu_info.debug_interface,
            "target/" .. mcu_info.openocd_target .. ".cfg"
        }
    }

    -- RTT configuration (OpenOCD + RTT console)
    local rtt_config = {
        name = "Debug (RTT)",
        type = "cortex-debug",
        request = "launch",
        servertype = "openocd",
        cwd = "${workspaceFolder}",
        executable = executable,
        runToEntryPoint = "main",
        showDevDebugOutput = "none",
        preLaunchTask = "Build (Debug)",
        device = mcu_info.device_name,
        rttConfig = {
            enabled = true,
            address = mcu_info.ram_origin,
            searchSize = rtt_opts.searchSize or rtt_defaults.searchSize,
            searchId = rtt_opts.searchId or rtt_defaults.searchId,
            rtt_start_retry = rtt_opts.rtt_start_retry or rtt_defaults.rtt_start_retry,
            polling_interval = rtt_opts.polling_interval or rtt_defaults.polling_interval,
            decoders = rtt_opts.decoders or {
                { port = 0, type = "console" }
            }
        },
        configFiles = {
            mcu_info.debug_interface,
            "target/" .. mcu_info.openocd_target .. ".cfg"
        }
    }

    -- pyOCD configuration
    local pyocd_config = {
        name = "Debug (PYOCD)",
        type = "cortex-debug",
        request = "launch",
        servertype = "pyocd",
        cwd = "${workspaceFolder}",
        executable = executable,
        runToEntryPoint = "main",
        showDevDebugOutput = "none",
        preLaunchTask = "Build (Debug)",
        device = mcu_info.device_name
    }

    -- Append managed configurations after user configurations
    table.insert(launch.configurations, openocd_config)
    table.insert(launch.configurations, rtt_config)
    table.insert(launch.configurations, pyocd_config)

    -- Renode configuration (only if MCU has renode_repl in database)
    if mcu_info.renode_repl then
        local gdb_port = 3333
        local resc_path = "build/" .. target_name .. "/debug/" .. target_name .. "_renode.resc"

        -- Generate the debug .resc script
        generate_debug_resc(resc_path, mcu_info.renode_repl, target_name, mcu_info.flash_origin, gdb_port)

        local renode_config = {
            name = "Debug (RENODE)",
            type = "cortex-debug",
            request = "launch",
            servertype = "external",
            gdbTarget = "localhost:" .. gdb_port,
            cwd = "${workspaceFolder}",
            executable = executable,
            runToEntryPoint = "main",
            showDevDebugOutput = "none",
            preLaunchTask = "Start Renode",
            device = mcu_info.device_name
        }

        table.insert(launch.configurations, renode_config)
    end

    json_file.save(launch_file, launch)
    print("launch.json updated!")
end
