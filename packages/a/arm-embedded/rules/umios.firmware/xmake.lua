-- umios.firmware: UMI OS firmware build rule
--
-- Automatically adds BSP sources, os_entry.cc, and library dependencies
-- required to build a UMI OS firmware binary. Inherits the `embedded` rule
-- for toolchain/MCU configuration.
--
-- Usage:
--   target("umi_os")
--       add_rules("umios.firmware")
--       set_values("embedded.mcu", "stm32f407vg")
--       set_values("embedded.linker_script", path.join(os.scriptdir(), "kernel.ld"))
--       set_values("umios.board", "stm32f4_disco")
--   target_end()

rule("umios.firmware")
    add_deps("embedded")

    on_load(function(target)
        -- ================================================================
        -- Resolve board name
        -- ================================================================

        local board = target:values("umios.board")
        if not board then
            raise("umios.firmware: set_values(\"umios.board\", \"<board_name>\") is required")
        end

        -- Project root (where xmake.lua lives)
        local project_dir = os.projectdir()

        -- ================================================================
        -- BSP source paths
        -- ================================================================

        local bsp_base = path.join(project_dir, "lib/umiport/src")

        -- Board-specific sources
        local board_dir = path.join(bsp_base, "board", board)
        if not os.isdir(board_dir) then
            raise("umios.firmware: board directory not found: %s", board_dir)
        end

        -- Required BSP sources for OS firmware
        local bsp_sources = {
            path.join(board_dir, "mcu.cc"),
            path.join(board_dir, "storage.cc"),
            path.join(bsp_base, "kernel/cortex_m4f_boot.cc"),
            path.join(bsp_base, "arch/cm4/handlers.cc"),
            path.join(bsp_base, "kernel/tcb_storage.cc"),
            path.join(bsp_base, "common/syscall_stubs.cc"),
        }

        -- OS entry point (main + extern "C" bridges)
        local os_entry = path.join(project_dir, "lib/umios/src/os_entry.cc")

        -- (loader and crypto are now header-only, no .cc files to compile)

        -- ================================================================
        -- Add sources
        -- ================================================================

        for _, src in ipairs(bsp_sources) do
            if os.isfile(src) then
                target:add("files", src)
            end
        end

        if os.isfile(os_entry) then
            target:add("files", os_entry)
        end

        -- (loader and crypto: header-only, included via headers)

        -- ================================================================
        -- Dependencies
        -- ================================================================

        target:add("deps", "umi.embedded.full")
        target:add("deps", "umios.runtime")
        target:add("deps", "umios.kernel")
        target:add("deps", "umidevice")
        target:add("deps", "umiport")
        target:add("deps", "umirtm")
        target:add("deps", "umidbg")

        -- ================================================================
        -- Defines
        -- ================================================================

        target:add("defines", "UMIOS_KERNEL=1")

        -- ================================================================
        -- Default settings
        -- ================================================================

        target:set("default", false)
        target:set("group", "examples")

        if not target:values("embedded.optimize") then
            target:set("values", "embedded.optimize", "size")
        end

        if not target:values("embedded.toolchain") then
            target:set("values", "embedded.toolchain", "gcc-arm")
        end
    end)

rule_end()
