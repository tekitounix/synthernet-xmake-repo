-- Generate a single normalized compile_commands.json for clangd.
--
-- Problem: xmake generates entries with ARM/WASM cross-compilers that clangd
-- cannot use directly (it always uses its own clang internally).
-- Previous approach split into host/arm/wasm databases with .clangd PathMatch,
-- but this required manual maintenance and didn't solve ARM-specific errors.
--
-- Solution: Normalize ALL entries to host clang-compatible format:
--   - Replace cross-compiler paths with host clang
--   - Remove ARM-specific flags (-mthumb, -mcpu, -mfpu, -mfloat-abi, --specs)
--   - Remove WASM-specific flags
--   - Preserve -I, -D, -std, -W flags (the parts clangd actually uses)
--   - Deduplicate: when same file appears in multiple targets, host entry wins
--
-- Result: One compile_commands.json that clangd uses without any .clangd
-- PathMatch configuration. Adding new targets "just works".
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

                -- 2. Find host clang path
                local host_clang = nil
                for _, e in ipairs(entries) do
                    local compiler = e.arguments and e.arguments[1] or ""
                    if compiler:find("clang") and not compiler:find("arm%-none%-eabi") and not compiler:find("emcc") then
                        host_clang = compiler
                        break
                    end
                end
                -- Fallback: use system clang
                if not host_clang then
                    host_clang = "clang++"
                end

                -- 3. Flags to remove from cross-compiled entries
                local remove_flags = {
                    -- ARM-specific
                    "%-mthumb", "%-mcpu=.*", "%-mfpu=.*", "%-mfloat%-abi=.*",
                    "%-%-specs=.*",
                    -- WASM-specific
                    "%-s%s+WASM=", "%-s%s+EXPORTED_FUNCTIONS",
                }
                -- Flags to remove from ALL entries (not just cross-compiled)
                local remove_flags_all = {
                    "%-Werror",       -- -Werror (standalone: promote all warnings to errors)
                    "%-Werror=.*",    -- -Werror=<diagnostic> (promote specific warning)
                }
                -- Flags that take a separate next argument
                local remove_next = {
                    ["-mcpu"] = true, ["-mfpu"] = true, ["-mfloat-abi"] = true,
                    ["--specs"] = true,
                }

                local function classify(e)
                    local compiler = e.arguments and e.arguments[1] or ""
                    if compiler:find("arm%-none%-eabi") then return "arm" end
                    if compiler:find("emcc") then return "wasm" end
                    if compiler:find("/%.xmake/packages/") then return "arm" end
                    return "host"
                end

                local function should_remove_cross(flag)
                    for _, pat in ipairs(remove_flags) do
                        if flag:match("^" .. pat .. "$") then return true end
                    end
                    return false
                end

                local function should_remove_all(flag)
                    for _, pat in ipairs(remove_flags_all) do
                        if flag:match("^" .. pat .. "$") then return true end
                    end
                    return false
                end

                -- Remove IDE-unfriendly flags (e.g. -Werror) from any entry
                local function sanitize(e)
                    local args = e.arguments
                    if not args then return e end
                    local new_args = {}
                    for _, arg in ipairs(args) do
                        if not should_remove_all(arg) then
                            table.insert(new_args, arg)
                        end
                    end
                    return {directory = e.directory, file = e.file, arguments = new_args}
                end

                -- Normalize cross-compiled entry to host clang
                local function normalize(e)
                    local args = e.arguments
                    if not args then return e end

                    local new_args = {host_clang}  -- replace compiler
                    local skip_next = false
                    for i = 2, #args do
                        if skip_next then
                            skip_next = false
                        elseif should_remove_cross(args[i]) or should_remove_all(args[i]) then
                            -- skip this flag
                        elseif remove_next[args[i]] then
                            skip_next = true  -- skip flag and its argument
                        elseif args[i] == "-I" and i < #args and args[i + 1]:find("/arm%-none%-eabi/") then
                            -- "-I" "/path/to/arm-none-eabi/..." as separate args — skip both
                            skip_next = true
                        elseif args[i]:find("^%-I.*/arm%-none%-eabi/") then
                            -- "-I/path/to/arm-none-eabi/..." as single arg — skip
                        else
                            table.insert(new_args, args[i])
                        end
                    end
                    return {
                        directory = e.directory,
                        file = e.file,
                        arguments = new_args
                    }
                end

                -- 4. Process entries: normalize cross-compiled, deduplicate (host wins)
                local seen = {}  -- file path -> {entry, platform}
                local counts = {host = 0, arm = 0, wasm = 0}

                for _, e in ipairs(entries) do
                    local platform = classify(e)
                    counts[platform] = counts[platform] + 1

                    local normalized = (platform == "host") and sanitize(e) or normalize(e)
                    local file = normalized.file

                    if not seen[file] then
                        seen[file] = {entry = normalized, platform = platform}
                    elseif platform == "host" then
                        -- Host entry wins over cross-compiled
                        seen[file] = {entry = normalized, platform = platform}
                    end
                    -- Otherwise keep existing (first cross-compiled entry)
                end

                -- 5. Collect and write single compdb
                local result = {}
                for _, v in pairs(seen) do
                    table.insert(result, v.entry)
                end

                local compdb_dir = path.join(os.projectdir(), "build", "compdb")
                os.mkdir(compdb_dir)
                json.savefile(path.join(compdb_dir, "compile_commands.json"), result, {indent = 2})

                -- 6. Clean up: remove root file and legacy per-platform dirs
                os.rm(compdb_path)
                for _, name in ipairs({"host", "arm", "wasm"}) do
                    local legacy_dir = path.join(compdb_dir, name)
                    if os.isdir(legacy_dir) then
                        os.rmdir(legacy_dir)
                    end
                end

                print("compdb: %d entries (host=%d, arm=%d, wasm=%d → normalized)",
                      #result, counts["host"], counts["arm"], counts["wasm"])

            end, {dependfile = dependfile,
                  files = table.join(project.allfiles(), config.filepath())})

            lockfile:close()
        end
    end)
