-- firmware: Manifest-driven firmware build rule
--
-- Generic replacement for project-specific firmware rules (e.g. umibm.firmware,
-- umios.firmware). Reads a JSON manifest to determine BSP sources, dependencies,
-- defines, and default build settings. Inherits the `embedded` rule for
-- toolchain/MCU configuration.
--
-- Manifest format (manifest.json):
--   {
--       "bsp_sources":       ["lib/umiport/src/board/${board}/mcu.cc", ...],
--       "extra_sources":     ["lib/umios/src/os_entry.cc"],
--       "dependencies":      ["umi.embedded.full", "umibm", ...],
--       "defines":           ["UMIOS_KERNEL=1"],
--       "default_optimize":  "size",
--       "default_toolchain": "gcc-arm"
--   }
--
-- The ${board} placeholder in source paths is resolved from firmware.board.
--
-- Usage:
--   target("my_firmware")
--       add_rules("firmware")
--       set_values("embedded.mcu", "stm32f407vg")
--       set_values("embedded.linker_script", path.join(os.scriptdir(), "kernel.ld"))
--       set_values("firmware.manifest", "lib/umibm/manifest.json")
--       set_values("firmware.board", "stm32f4_disco")
--       add_files("src/main.cc")
--   target_end()

rule("firmware")
    add_deps("embedded")

    on_load(function(target)
        -- ================================================================
        -- Read manifest path (required)
        -- ================================================================

        local manifest_path = target:values("firmware.manifest")
        if not manifest_path then
            raise("firmware: set_values(\"firmware.manifest\", \"path/to/manifest.json\") is required")
        end

        local board = target:values("firmware.board")
        -- board can be nil if manifest doesn't use ${board}

        local project_dir = os.projectdir()

        -- ================================================================
        -- Load manifest JSON
        -- ================================================================

        import("core.base.json")
        local manifest_file = path.join(project_dir, manifest_path)
        if not os.isfile(manifest_file) then
            raise("firmware: manifest not found: %s", manifest_file)
        end
        local content = io.readfile(manifest_file)
        local manifest = json.decode(content)

        -- ================================================================
        -- Helper: resolve ${board} placeholder and make absolute path
        -- ================================================================

        local function resolve_path(p)
            if board then
                p = p:gsub("%${board}", board)
            end
            return path.join(project_dir, p)
        end

        -- ================================================================
        -- Add BSP sources
        -- ================================================================

        for _, src in ipairs(manifest.bsp_sources or {}) do
            local resolved = resolve_path(src)
            if os.isfile(resolved) then
                target:add("files", resolved)
            end
        end

        -- ================================================================
        -- Add extra sources
        -- ================================================================

        for _, src in ipairs(manifest.extra_sources or {}) do
            local resolved = resolve_path(src)
            if os.isfile(resolved) then
                target:add("files", resolved)
            end
        end

        -- ================================================================
        -- Dependencies
        -- ================================================================

        for _, dep in ipairs(manifest.dependencies or {}) do
            target:add("deps", dep)
        end

        -- ================================================================
        -- Defines
        -- ================================================================

        for _, def in ipairs(manifest.defines or {}) do
            target:add("defines", def)
        end

        -- ================================================================
        -- Default settings
        -- ================================================================

        target:set("default", false)
        target:set("group", "examples")

        if not target:values("embedded.optimize") then
            target:set("values", "embedded.optimize", manifest.default_optimize or "size")
        end

        if not target:values("embedded.toolchain") then
            target:set("values", "embedded.toolchain", manifest.default_toolchain or "gcc-arm")
        end
    end)

rule_end()
