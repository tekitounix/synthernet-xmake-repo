-- Generate a single normalized compile_commands.json for clangd.
--
-- Problem: xmake generates entries with ARM/WASM cross-compilers that clangd
-- cannot use directly (it always uses its own clang internally).
-- Previous approach split into host/arm/wasm databases with .clangd PathMatch,
-- but this required manual maintenance and didn't solve ARM-specific errors.
--
-- Solution: Normalize ALL entries to host clang-compatible format:
--   - Replace cross-compiler paths with host clang
--   - Whitelist approach: keep only flags clangd uses (-I, -isystem, -D, -std, -W, -x, -c)
--   - Include paths filtered by location (project-local + host SDK only)
--   - Architecture-agnostic: no blacklist of target-specific flags to maintain
--   - Deduplicate: when same file appears in multiple targets, host entry wins
--   - Path normalization: resolve ../ for consistent dedup and clangd matching
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

            -- Collect public include dirs (outside depend.on_changed for values parameter)
            local function build_global_include_set()
                local inc_flags = {}
                local inc_dirs = {}
                local flags = {}
                local sorted_targets = {}
                for name, target in pairs(project.targets()) do
                    table.insert(sorted_targets, {name = name, target = target})
                end
                table.sort(sorted_targets, function(a, b) return a.name < b.name end)
                for _, item in ipairs(sorted_targets) do
                    local target = item.target
                    for _, dir in ipairs(table.wrap(target:get("includedirs"))) do
                        local extraconf = target:extraconf("includedirs", dir)
                        if not (extraconf and extraconf.public) then
                            goto continue
                        end
                        local abs = path.absolute(dir)
                        if not abs:startswith(os.projectdir()) then
                            goto continue
                        end
                        local rel = path.relative(abs, os.projectdir())
                        local flag = "-I" .. rel
                        if not inc_flags[flag] then
                            inc_flags[flag] = true
                            table.insert(inc_dirs, rel)
                            table.insert(flags, flag)
                        end
                        ::continue::
                    end
                end
                return flags, inc_dirs
            end

            local inc_flag_list, inc_dirs = build_global_include_set()

            -- Build header file list for depend.on_changed values parameter
            local header_file_list = {}
            for _, dir in ipairs(inc_dirs) do
                if os.isdir(dir) then
                    for _, hdr in ipairs(os.files(path.join(dir, "**.hh"))) do
                        table.insert(header_file_list, hdr)
                    end
                end
            end
            table.sort(header_file_list)

            depend.on_changed(function ()

                -- 1. Generate compile_commands.json via xmake's project task (in-process)
                task.run("project", {kind = "compile_commands", outputdir = os.projectdir(), lsp = "clangd"})

                local compdb_path = path.join(os.projectdir(), "compile_commands.json")
                if not os.isfile(compdb_path) then
                    return
                end
                local entries = json.loadfile(compdb_path)

                -- 2. Find host clang path and -isysroot
                local host_clang = nil
                local host_isysroot = nil
                for _, e in ipairs(entries) do
                    local compiler = e.arguments and e.arguments[1] or ""
                    if compiler:find("clang") and not compiler:find("arm%-none%-eabi") and not compiler:find("emcc") then
                        host_clang = compiler
                        -- Extract -isysroot from host entry for use in normalized entries
                        for i, arg in ipairs(e.arguments) do
                            if arg == "-isysroot" and e.arguments[i + 1] then
                                host_isysroot = e.arguments[i + 1]
                            end
                        end
                        break
                    end
                end
                -- Fallback: use system clang
                if not host_clang then
                    host_clang = "clang++"
                end

                -- Generate header entries (needs host_clang/host_isysroot from above)
                -- inc_flag_list, inc_dirs captured via closure from outer scope
                local function generate_header_entries(dirs, flags, clang, isysroot)
                    local hdr_entries = {}
                    local hdr_seen = {}
                    for _, dir in ipairs(dirs) do
                        if not os.isdir(dir) then goto next_dir end
                        for _, hdr in ipairs(os.files(path.join(dir, "**.hh"))) do
                            if not hdr_seen[hdr] then
                                hdr_seen[hdr] = true
                                local args = {clang}
                                if isysroot then
                                    table.insert(args, "-isysroot")
                                    table.insert(args, isysroot)
                                end
                                for _, f in ipairs(flags) do
                                    table.insert(args, f)
                                end
                                table.insert(args, "-std=c++23")
                                table.insert(args, "-x")
                                table.insert(args, "c++-header")
                                table.insert(args, hdr)
                                table.insert(hdr_entries, {
                                    directory = os.projectdir(),
                                    file = hdr,
                                    arguments = args
                                })
                            end
                        end
                        ::next_dir::
                    end
                    return hdr_entries
                end

                local header_entries = generate_header_entries(
                    inc_dirs, inc_flag_list, host_clang, host_isysroot)

                -- 3. Classify entry by platform
                local function classify(e)
                    local compiler = e.arguments and e.arguments[1] or ""
                    if compiler:find("arm%-none%-eabi") then return "arm" end
                    if compiler:find("emcc") then return "wasm" end
                    if compiler:find("/%.xmake/packages/") then return "arm" end
                    return "host"
                end

                -- Is this include path useful for clangd on the host?
                -- Architecture-agnostic: keeps project-local and host SDK paths,
                -- rejects any cross-toolchain path (ARM, WASM, RISC-V, etc.)
                local function is_relevant_include(dir)
                    if not dir:startswith("/") then return true end
                    if dir:startswith(os.projectdir()) then return true end
                    if host_isysroot and dir:startswith(host_isysroot) then return true end
                    return false
                end

                -- Remove -Werror from host entries (already valid for clangd)
                local function sanitize(e)
                    local args = e.arguments
                    if not args then return e end
                    local new_args = {}
                    for _, arg in ipairs(args) do
                        if not (arg == "-Werror" or arg:match("^%-Werror=")) then
                            table.insert(new_args, arg)
                        end
                    end
                    return {directory = e.directory, file = e.file, arguments = new_args}
                end

                -- Normalize cross-compiled entry to host clang (whitelist approach).
                -- Only keeps flags that clangd uses for semantic analysis.
                -- Architecture-agnostic: works for ARM, WASM, RISC-V, or any future
                -- target without maintaining a blacklist of target-specific flags.
                local function normalize(e)
                    local args = e.arguments
                    if not args then return e end

                    local new_args = {host_clang}
                    if host_isysroot then
                        table.insert(new_args, "-isysroot")
                        table.insert(new_args, host_isysroot)
                    end

                    local i = 2
                    while i <= #args do
                        local arg = args[i]
                        -- Include paths: keep project-local and host SDK only
                        if arg == "-I" or arg == "-isystem" then
                            local next_arg = args[i + 1]
                            if next_arg and is_relevant_include(next_arg) then
                                table.insert(new_args, arg)
                                table.insert(new_args, next_arg)
                            end
                            i = i + 2
                        elseif arg:match("^%-I(.+)") then
                            if is_relevant_include(arg:sub(3)) then
                                table.insert(new_args, arg)
                            end
                            i = i + 1
                        -- Preprocessor defines: always keep
                        elseif arg == "-D" then
                            table.insert(new_args, arg)
                            if args[i + 1] then
                                table.insert(new_args, args[i + 1])
                            end
                            i = i + 2
                        elseif arg:match("^%-D") then
                            table.insert(new_args, arg)
                            i = i + 1
                        -- Language standard: always keep
                        elseif arg:match("^%-std=") then
                            table.insert(new_args, arg)
                            i = i + 1
                        -- Warnings: keep (except -Werror which promotes to errors)
                        elseif arg:match("^%-W") and not arg:match("^%-Werror") then
                            table.insert(new_args, arg)
                            i = i + 1
                        -- Language mode: keep -x and its argument
                        elseif arg == "-x" then
                            table.insert(new_args, arg)
                            i = i + 1
                            if args[i] then
                                table.insert(new_args, args[i])
                                i = i + 1
                            end
                        -- Compile-only flag: keep
                        elseif arg == "-c" then
                            table.insert(new_args, arg)
                            i = i + 1
                        -- Output file: skip -o and its argument
                        elseif arg == "-o" then
                            i = i + 2
                        -- Non-flag argument (source file path): keep
                        elseif not arg:match("^%-") then
                            table.insert(new_args, arg)
                            i = i + 1
                        -- Everything else (arch, optimization, codegen flags): skip
                        else
                            i = i + 1
                        end
                    end

                    return {directory = e.directory, file = e.file, arguments = new_args}
                end

                -- 4. Process entries: normalize cross-compiled, deduplicate (host wins)
                local seen = {}  -- file path -> {entry, platform}
                local counts = {host = 0, arm = 0, wasm = 0}

                for _, e in ipairs(entries) do
                    local platform = classify(e)
                    counts[platform] = counts[platform] + 1

                    local normalized = (platform == "host") and sanitize(e) or normalize(e)

                    -- Normalize file path: resolve ../ for consistent dedup and clangd matching
                    local file = normalized.file
                    if file and file:find("%.%./") then
                        local abs = path.absolute(file, os.projectdir())
                        file = path.relative(abs, os.projectdir())
                        normalized.file = file
                        -- Also fix source file in arguments (usually last element)
                        local args = normalized.arguments
                        if args and args[#args] and args[#args]:find("%.%./") then
                            args[#args] = file
                        end
                    end

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

                -- Append header entries directly to result
                for _, he in ipairs(header_entries) do
                    table.insert(result, he)
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

                print("compdb: %d entries (src: host=%d, arm=%d, wasm=%d normalized | headers=%d direct)",
                      #result, counts["host"], counts["arm"], counts["wasm"], #header_entries)

            end, {dependfile = dependfile,
                  files = table.join(project.allfiles(), config.filepath()),
                  values = header_file_list})

            lockfile:close()
        end
    end)
