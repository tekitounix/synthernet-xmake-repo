-- Auto-split compile_commands.json into per-platform databases after build.
--
-- Uses xmake's built-in project task to generate compile_commands.json,
-- then splits into host/arm/wasm for clangd PathMatch.
-- Only re-splits when source files or build config change.
--
-- Usage: add_rules("embedded.compdb") in project xmake.lua

rule("embedded.compdb")
    set_kind("project")
    after_build(function (opt)

        import("core.base.json")
        import("core.base.task")
        import("core.project.config")
        import("core.project.depend")
        import("core.project.project")

        if os.getenv("XMAKE_IN_XREPO") then
            return
        end

        local tmpfile = path.join(config.builddir(), ".gens", "rules", "embedded.compdb")
        local dependfile = tmpfile .. ".d"
        local lockfile = io.openlock(tmpfile .. ".lock")
        if lockfile:trylock() then
            depend.on_changed(function ()

                -- 1. Generate compile_commands.json via xmake's project task (in-process)
                task.run("project", {kind = "compile_commands", outputdir = os.projectdir()})

                local compdb_path = path.join(os.projectdir(), "compile_commands.json")
                if not os.isfile(compdb_path) then
                    return
                end
                local entries = json.loadfile(compdb_path)

                -- 2. Classify each entry by platform
                local buckets = { host = {}, arm = {}, wasm = {} }

                local function classify(e)
                    local compiler = e.arguments and e.arguments[1] or ""
                    if compiler:find("arm%-none%-eabi") then return "arm" end
                    if compiler:find("emcc") then return "wasm" end
                    if compiler:find("/%.xmake/packages/") then return "arm" end
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

                -- 4. Remove root (mixed targets cause problems for all tools)
                os.rm(compdb_path)

                print("compdb: host=%d, arm=%d, wasm=%d",
                      #buckets["host"], #buckets["arm"], #buckets["wasm"])

            end, {dependfile = dependfile,
                  files = table.join(project.allfiles(), config.filepath())})

            lockfile:close()
        end
    end)
