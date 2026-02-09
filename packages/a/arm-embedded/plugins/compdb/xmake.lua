-- Generate per-platform compile_commands.json for clangd multi-target support.
--
-- Output:
--   build/compdb/host/compile_commands.json  -- host clang entries
--   build/compdb/arm/compile_commands.json   -- clang-arm + gcc-arm entries
--   build/compdb/wasm/compile_commands.json  -- emcc entries
--
-- No root compile_commands.json is generated. All consumers (clangd, clang-tidy, etc.)
-- should use the per-platform databases via .clangd PathMatch or explicit -p flag.
--
-- Usage: xmake compdb

task("compdb")
    set_category("plugin")
    set_menu {
        usage = "xmake compdb",
        description = "Generate per-platform compile_commands.json for clangd"
    }
    on_run(function ()
        import("core.base.json")

        -- 1. Generate raw compile_commands.json via xmake (temporary)
        os.execv("xmake", {"project", "-k", "compile_commands", "."})

        local compdb_path = path.join(os.projectdir(), "compile_commands.json")
        local entries = json.loadfile(compdb_path)

        -- 2. Classify each entry by platform
        local buckets = { host = {}, arm = {}, wasm = {} }

        local function classify(e)
            local compiler = e.arguments and e.arguments[1] or ""
            if compiler:find("arm%-none%-eabi") then return "arm" end
            if compiler:find("emcc") then return "wasm" end
            if compiler:find("/%.xmake/packages/") then return "arm" end  -- clang-arm
            return "host"
        end

        for _, e in ipairs(entries) do
            table.insert(buckets[classify(e)], e)
        end

        -- 3. Write per-platform databases
        local compdb_dir = path.join(os.projectdir(), "build", "compdb")

        for name, db_entries in pairs(buckets) do
            local dir = path.join(compdb_dir, name)
            os.mkdir(dir)
            json.savefile(path.join(dir, "compile_commands.json"), db_entries, {indent = 2})
        end

        -- 4. Remove root compile_commands.json (mixed targets cause problems for all tools)
        os.rm(compdb_path)

        print("compdb: host=%d, arm=%d, wasm=%d",
              #buckets["host"], #buckets["arm"], #buckets["wasm"])
    end)
