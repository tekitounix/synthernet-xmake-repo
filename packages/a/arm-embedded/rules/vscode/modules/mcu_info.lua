-- MCU information resolver for VSCode debug configuration.
-- Resolves MCU-specific settings from mcu-database.json with fallback derivation,
-- supporting multi-vendor Cortex-M targets and Renode simulation.

import("core.base.json")

-- Parse a size string like "128K" or "1M" into bytes.
local function parse_size(s)
    if not s then return 0 end
    local num, unit = s:match("^(%d+)(%a?)$")
    num = tonumber(num)
    if not num then return 0 end
    if unit == "K" or unit == "k" then return num * 1024 end
    if unit == "M" or unit == "m" then return num * 1024 * 1024 end
    return num
end

-- Derive OpenOCD target config from MCU name using STM32 naming convention.
-- e.g. "stm32f407vg" -> "stm32f4x"
local function derive_openocd_target(mcu_lower)
    -- STM32 pattern: stm32[family][sub]... -> stm32[family]x
    local family = mcu_lower:match("^(stm32%a%d)")
    if family then
        return family .. "x"
    end
    return nil
end

-- Default debug probe interface by vendor.
local vendor_probes = {
    st  = "interface/stlink.cfg",
    nxp = "interface/cmsis-dap.cfg",
}
local default_probe = "interface/cmsis-dap.cfg"

-- Resolve MCU information for debug configuration.
--
-- @param mcu_db_path  Path to mcu-database.json
-- @param mcu_name     MCU identifier (e.g. "stm32f407vg")
-- @param overrides    Optional table { probe = "...", openocd_target = "..." }
-- @return table       { device_name, openocd_target, debug_interface, ram_origin, ram_bytes, flash_origin, renode_repl }
function resolve(mcu_db_path, mcu_name, overrides)
    overrides = overrides or {}
    local mcu_lower = string.lower(mcu_name)

    -- Load database
    local db_entry = nil
    if os.isfile(mcu_db_path) then
        local db = try { function() return json.loadfile(mcu_db_path) end }
        if db and db.CONFIGS then
            db_entry = db.CONFIGS[mcu_lower]
        end
    end

    -- Resolve each field: overrides > DB > fallback
    local result = {}

    -- device_name
    if db_entry and db_entry.device_name then
        result.device_name = db_entry.device_name
    else
        result.device_name = string.upper(mcu_name)
    end

    -- openocd_target
    if overrides.openocd_target then
        result.openocd_target = overrides.openocd_target
    elseif db_entry and db_entry.openocd_target then
        result.openocd_target = db_entry.openocd_target
    else
        result.openocd_target = derive_openocd_target(mcu_lower) or mcu_lower
    end

    -- debug_interface (probe)
    if overrides.probe then
        result.debug_interface = overrides.probe
    else
        local vendor = db_entry and db_entry.vendor
        result.debug_interface = vendor_probes[vendor] or default_probe
    end

    -- ram_origin
    if db_entry and db_entry.ram_origin then
        result.ram_origin = db_entry.ram_origin
    else
        result.ram_origin = "0x20000000"
    end

    -- ram_bytes (for RTT searchSize)
    if db_entry and db_entry.ram then
        result.ram_bytes = parse_size(db_entry.ram)
    else
        result.ram_bytes = 131072  -- 128K default
    end

    -- flash_origin (for Renode VTOR setup)
    if db_entry and db_entry.flash_origin then
        result.flash_origin = db_entry.flash_origin
    else
        result.flash_origin = "0x08000000"
    end

    -- renode_repl (nil if Renode not supported for this MCU)
    if db_entry and db_entry.renode_repl then
        result.renode_repl = db_entry.renode_repl
    end

    return result
end
