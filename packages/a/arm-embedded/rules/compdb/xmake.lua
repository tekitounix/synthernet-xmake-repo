-- Generate a single normalized compile_commands.json for clangd.
--
-- v4: Target-Aware normalization
--
-- Problem: clangd/clang-tidy always uses host clang internally, regardless of
-- the compiler path in compdb. Previous v3 approach stripped all target info,
-- causing false positives for section attributes, alias, pointer casts, etc.
--
-- Solution: Normalize entries with --target=<triple> so host clang acts as a
-- cross-compiler. ARM GCC libstdc++ paths are preserved via -nostdinc++ and
-- -isystem. This eliminates all false positives from host/target mismatch.
--
-- Design: See lib/docs/design/COMPDB_TARGET_AWARE.md
--
-- Usage: add_rules("embedded.compdb") in project xmake.lua

rule("embedded.compdb")
    set_kind("project")
    after_build(function (opt)

        import("core.base.global")
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

            -- §3.1: Common utilities

            --- Check if filepath is under a directory prefix (with boundary check).
            --- Prevents "/foo/bar" matching "/foo/barbaz/".
            local function is_under_dir(filepath, prefix)
                if not filepath:startswith(prefix) then return false end
                local next_pos = #prefix + 1
                if next_pos > #filepath then return true end  -- exact match
                return filepath:sub(next_pos, next_pos) == "/"
            end

            --- Map triple to platform type.
            local function platform_from_triple(triple)
                if triple:find("^thumb") or triple:find("^arm") then return "arm" end
                if triple:find("^riscv") then return "riscv" end
                if triple:find("wasm") then return "wasm" end
                return "cross"
            end

            --- Extract SemVer from path as comparable number.
            --- Uses last match to handle nested version directories.
            local function version_number_from_path(p)
                local last_major, last_minor, last_patch
                for major, minor, patch in p:gmatch("/v?(%d+)%.(%d+)%.(%d+)/") do
                    last_major, last_minor, last_patch = major, minor, patch
                end
                if last_major then
                    return tonumber(last_major) * 1000000 + tonumber(last_minor) * 1000 + tonumber(last_patch)
                end
                return 0
            end

            -- §3.2: Target metadata collection

            --- Build file->metadata and target->metadata maps from xmake targets.
            --- Collects triple, sysincludedirs, and includedirs (direct + transitive deps).
            local function build_target_metadata()
                local file_meta = {}
                local target_meta = {}

                -- Sort target names for deterministic representative selection
                local sorted_names = {}
                for name, _ in pairs(project.targets()) do
                    table.insert(sorted_names, name)
                end
                table.sort(sorted_names)

                for _, name in ipairs(sorted_names) do
                    local target = project.targets()[name]
                    local triple = target:data("embedded_target_triple")
                    if triple then
                        local plat = platform_from_triple(triple)

                        -- Collect sysincludedirs (absolute paths)
                        local sysincludedirs = {}
                        for _, dir in ipairs(table.wrap(target:get("sysincludedirs"))) do
                            table.insert(sysincludedirs, path.absolute(dir))
                        end

                        -- Collect includedirs: direct + transitive deps' public includedirs
                        local includedirs = {}
                        for _, dir in ipairs(table.wrap(target:get("includedirs"))) do
                            table.insert(includedirs, path.absolute(dir))
                        end
                        for _, dep in ipairs(target:orderdeps()) do
                            for _, dir in ipairs(table.wrap(dep:get("includedirs"))) do
                                local extraconf = dep:extraconf("includedirs", dir)
                                if extraconf and extraconf.public then
                                    table.insert(includedirs, path.absolute(dir))
                                end
                            end
                        end

                        local meta = {
                            triple = triple,
                            sysincludedirs = sysincludedirs,
                            includedirs = includedirs,
                            target_name = name,
                            platform = plat,
                        }

                        target_meta[name] = meta

                        -- First target (alphabetically) wins for same file
                        for _, srcfile in ipairs(target:sourcefiles()) do
                            local rel = path.relative(path.absolute(srcfile), os.projectdir())
                            if not file_meta[rel] then
                                file_meta[rel] = meta
                            end
                        end
                    end
                end

                -- Inherit sysincludedirs from sibling targets on same platform
                -- (some targets may lack sysincludedirs depending on toolchain config)
                local platform_sysincludedirs = {}
                for _, meta in pairs(target_meta) do
                    if #meta.sysincludedirs > 0 then
                        local existing = platform_sysincludedirs[meta.platform]
                        if not existing or #meta.sysincludedirs > #existing then
                            platform_sysincludedirs[meta.platform] = meta.sysincludedirs
                        end
                    end
                end
                for _, meta in pairs(target_meta) do
                    if #meta.sysincludedirs == 0 and platform_sysincludedirs[meta.platform] then
                        meta.sysincludedirs = platform_sysincludedirs[meta.platform]
                    end
                end

                return file_meta, target_meta
            end

            -- §3.3: Fallback triple resolution from compiler flags

            --- Resolve triple from -mcpu/-mfloat-abi flags using cortex-m.json.
            local function resolve_triple_from_flags(args, cortex_db)
                if not cortex_db then return nil end

                local cpu = nil
                local float_abi = nil

                for _, arg in ipairs(args) do
                    if arg:match("^%-mcpu=") then
                        cpu = arg:sub(7)
                    elseif arg:match("^%-mfloat%-abi=") then
                        float_abi = arg:sub(14)
                    end
                end

                if not cpu then return nil end

                if float_abi == "hard" then
                    local fpu_core = cortex_db.cores[cpu .. "f"]
                    if fpu_core then return fpu_core.target end
                end
                local core = cortex_db.cores[cpu]
                if core then return core.target end

                return nil
            end

            -- §3.4: cortex-m.json database loading

            --- Load cortex-m.json from dev-sync path or package install path.
            local function load_cortex_database()
                -- Priority 1: dev-sync path (latest during development)
                local devsync = path.join(global.directory(), "rules", "embedded", "database", "cortex-m.json")
                if os.isfile(devsync) then
                    return json.loadfile(devsync)
                end

                -- Priority 2: package install path (SemVer numeric sort, newest first)
                local pkg_pattern = path.join(global.directory(), "packages", "a", "arm-embedded",
                                               "*", "*", "rules", "embedded", "database", "cortex-m.json")
                local pkg_candidates = os.files(pkg_pattern)
                if #pkg_candidates > 0 then
                    table.sort(pkg_candidates, function(a, b)
                        return version_number_from_path(a) > version_number_from_path(b)
                    end)
                    return json.loadfile(pkg_candidates[1])
                end

                return nil
            end

            -- §3.5: Cross-toolchain sysinclude detection

            --- Check if a directory is a cross-toolchain system include path.
            local function is_cross_sysinclude(dir)
                if dir:find("arm%-none%-eabi") then return true end
                if dir:find("gcc%-arm") then return true end
                if dir:find("riscv") and dir:find("none%-elf") then return true end
                return false
            end

            -- §3.6: Platform classification

            --- Classify compdb entry by compiler path (origin detection).
            local function classify(e)
                local compiler = e.arguments and e.arguments[1] or ""
                if compiler:find("arm%-none%-eabi") then return "arm" end
                if compiler:find("emcc") then return "wasm" end
                if compiler:find("/%.xmake/packages/") then return "arm" end
                return "host"
            end

            -- §3.7: Include path filters

            --- Check if path is project-local.
            local function is_project_include(dir)
                if not dir:startswith("/") then return true end
                return is_under_dir(dir, os.projectdir())
            end

            --- Check if -isystem path should be kept in normalized entry.
            local function is_relevant_include(dir, classify_platform, has_triple, host_isysroot)
                if not dir:startswith("/") then return true end
                if is_under_dir(dir, os.projectdir()) then return true end

                if classify_platform == "host" then
                    return host_isysroot and is_under_dir(dir, host_isysroot)
                elseif classify_platform == "wasm" then
                    return dir:find("emscripten") ~= nil
                elseif has_triple then
                    return is_cross_sysinclude(dir)
                end

                return host_isysroot and is_under_dir(dir, host_isysroot)
            end

            -- §3.8: Header platform estimation

            --- Estimate header file's platform from metadata maps.
            local function classify_header(header_path, file_meta, target_meta)
                local abs_header = path.absolute(header_path)

                -- Stage 1: Same-directory source file inheritance
                local dir = path.directory(header_path)
                local candidate = nil
                for file, meta in pairs(file_meta) do
                    if path.directory(file) == dir then
                        if not candidate or meta.target_name < candidate.target_name then
                            candidate = meta
                        end
                    end
                end
                if candidate then return candidate end

                -- Stage 2: Target includedirs prefix match
                local sorted_target_names = {}
                for tname, _ in pairs(target_meta) do
                    table.insert(sorted_target_names, tname)
                end
                table.sort(sorted_target_names)

                for _, tname in ipairs(sorted_target_names) do
                    local meta = target_meta[tname]
                    if meta.includedirs then
                        for _, incdir in ipairs(meta.includedirs) do
                            if is_under_dir(abs_header, incdir) then
                                return meta
                            end
                        end
                    end
                end

                -- Stage 3: Default to host
                return nil
            end

            -- §3.9: Normalization

            --- Normalize a compdb entry for host clang analysis.
            local function normalize_entry(e, meta, platform, cortex_db, host_clang, host_isysroot)
                local args = e.arguments
                if not args then return e end

                local new_args = {host_clang}
                local triple = nil

                if platform ~= "host" then
                    triple = meta and meta.triple
                    if not triple and platform == "arm" then
                        triple = resolve_triple_from_flags(args, cortex_db)
                    end

                    if triple then
                        table.insert(new_args, "--target=" .. triple)
                        table.insert(new_args, "-nostdinc++")

                        if meta and meta.sysincludedirs and #meta.sysincludedirs > 0 then
                            for _, dir in ipairs(meta.sysincludedirs) do
                                table.insert(new_args, "-isystem")
                                table.insert(new_args, dir)
                            end
                        end
                    else
                        if host_isysroot then
                            table.insert(new_args, "-isysroot")
                            table.insert(new_args, host_isysroot)
                        end
                    end
                else
                    if host_isysroot then
                        table.insert(new_args, "-isysroot")
                        table.insert(new_args, host_isysroot)
                    end
                end

                local has_triple = (triple ~= nil)
                local classify_platform = platform

                local i = 2
                while i <= #args do
                    local arg = args[i]

                    if arg == "-isystem" then
                        local next_arg = args[i + 1]
                        if next_arg then
                            if is_relevant_include(next_arg, classify_platform, has_triple, host_isysroot) then
                                table.insert(new_args, "-isystem")
                                table.insert(new_args, next_arg)
                            end
                        end
                        i = i + 2

                    elseif arg == "-I" then
                        local next_arg = args[i + 1]
                        if next_arg and is_project_include(next_arg) then
                            table.insert(new_args, arg)
                            table.insert(new_args, next_arg)
                        end
                        i = i + 2
                    elseif arg:match("^%-I(.+)") then
                        if is_project_include(arg:sub(3)) then
                            table.insert(new_args, arg)
                        end
                        i = i + 1

                    elseif arg == "-D" then
                        table.insert(new_args, arg)
                        if args[i + 1] then
                            table.insert(new_args, args[i + 1])
                        end
                        i = i + 2
                    elseif arg:match("^%-D") then
                        table.insert(new_args, arg)
                        i = i + 1

                    elseif arg:match("^%-std=") then
                        table.insert(new_args, arg)
                        i = i + 1

                    elseif arg:match("^%-W") and not arg:match("^%-Werror") then
                        table.insert(new_args, arg)
                        i = i + 1

                    elseif arg == "-fno-exceptions" or arg == "-fno-rtti"
                        or arg == "-fno-threadsafe-statics" then
                        table.insert(new_args, arg)
                        i = i + 1

                    elseif arg == "-x" then
                        table.insert(new_args, arg)
                        i = i + 1
                        if args[i] then table.insert(new_args, args[i]); i = i + 1 end

                    elseif arg == "-c" then
                        table.insert(new_args, arg)
                        i = i + 1

                    elseif arg == "-o" then
                        i = i + 2

                    elseif not arg:match("^%-") then
                        table.insert(new_args, arg)
                        i = i + 1

                    else
                        i = i + 1
                    end
                end

                return {directory = e.directory, file = e.file, arguments = new_args}
            end

            -- Collect public include dirs for header entry generation
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

                -- 1. Generate raw compile_commands.json via xmake's project task
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
                        for i, arg in ipairs(e.arguments) do
                            if arg == "-isysroot" and e.arguments[i + 1] then
                                host_isysroot = e.arguments[i + 1]
                            end
                        end
                        break
                    end
                end
                if not host_clang then
                    host_clang = "clang++"
                end

                -- 3. Build target metadata and load cortex database
                local cortex_db = load_cortex_database()
                local file_meta, target_meta = build_target_metadata()

                -- 4. Process source entries
                local seen = {}
                local counts = {host = 0, arm = 0, wasm = 0, cross_with_triple = 0}

                for _, e in ipairs(entries) do
                    local classify_platform = classify(e)
                    counts[classify_platform] = (counts[classify_platform] or 0) + 1

                    local file = e.file
                    if file and file:find("%.%./") then
                        file = path.relative(path.absolute(file, os.projectdir()), os.projectdir())
                    end

                    local meta = file_meta[file]

                    -- Host immutability (principle 8)
                    local platform = classify_platform
                    if classify_platform ~= "host" and meta and meta.triple then
                        platform = meta.platform
                    end

                    local normalized
                    if classify_platform == "host" then
                        local args = e.arguments
                        if args then
                            local new_args = {}
                            for _, arg in ipairs(args) do
                                if not (arg == "-Werror" or arg:match("^%-Werror=")) then
                                    table.insert(new_args, arg)
                                end
                            end
                            normalized = {directory = e.directory, file = file, arguments = new_args}
                        else
                            normalized = {directory = e.directory, file = file, arguments = args}
                        end
                    else
                        normalized = normalize_entry(e, meta, platform, cortex_db, host_clang, host_isysroot)
                        normalized.file = file
                        if meta and meta.triple then
                            counts.cross_with_triple = counts.cross_with_triple + 1
                        end
                    end

                    if file ~= e.file and normalized.arguments then
                        local args = normalized.arguments
                        if args[#args] and args[#args]:find("%.%./") then
                            args[#args] = file
                        end
                    end

                    if not seen[file] then
                        seen[file] = {entry = normalized, is_host = (classify_platform == "host")}
                    elseif classify_platform == "host" then
                        seen[file] = {entry = normalized, is_host = true}
                    end
                end

                -- 5. Collect source entries
                local result = {}
                for _, v in pairs(seen) do
                    table.insert(result, v.entry)
                end

                -- 6. Generate header entries with platform awareness
                local hdr_seen = {}
                local hdr_counts = {host = 0, cross = 0}
                for _, dir in ipairs(inc_dirs) do
                    if not os.isdir(dir) then goto next_dir end
                    for _, hdr in ipairs(os.files(path.join(dir, "**.hh"))) do
                        if hdr_seen[hdr] then goto next_hdr end
                        hdr_seen[hdr] = true

                        local meta = classify_header(hdr, file_meta, target_meta)
                        if meta then
                            local args = {host_clang, "--target=" .. meta.triple, "-nostdinc++"}
                            for _, sysdir in ipairs(meta.sysincludedirs) do
                                table.insert(args, "-isystem")
                                table.insert(args, sysdir)
                            end
                            for _, incdir in ipairs(meta.includedirs) do
                                table.insert(args, "-I")
                                table.insert(args, incdir)
                            end
                            table.insert(args, "-std=c++23")
                            table.insert(args, "-x")
                            table.insert(args, "c++-header")
                            table.insert(args, hdr)
                            table.insert(result, {directory = os.projectdir(), file = hdr, arguments = args})
                            hdr_counts.cross = hdr_counts.cross + 1
                        else
                            local args = {host_clang}
                            if host_isysroot then
                                table.insert(args, "-isysroot")
                                table.insert(args, host_isysroot)
                            end
                            for _, f in ipairs(inc_flag_list) do
                                table.insert(args, f)
                            end
                            table.insert(args, "-std=c++23")
                            table.insert(args, "-x")
                            table.insert(args, "c++-header")
                            table.insert(args, hdr)
                            table.insert(result, {directory = os.projectdir(), file = hdr, arguments = args})
                            hdr_counts.host = hdr_counts.host + 1
                        end

                        ::next_hdr::
                    end
                    ::next_dir::
                end

                -- 7. Write single compdb
                local compdb_dir = path.join(os.projectdir(), "build", "compdb")
                os.mkdir(compdb_dir)
                json.savefile(path.join(compdb_dir, "compile_commands.json"), result, {indent = 2})

                -- 8. Clean up
                os.rm(compdb_path)
                for _, name in ipairs({"host", "arm", "wasm"}) do
                    local legacy_dir = path.join(compdb_dir, name)
                    if os.isdir(legacy_dir) then
                        os.rmdir(legacy_dir)
                    end
                end

                local total_hdrs = hdr_counts.host + hdr_counts.cross
                print("compdb: %d entries (src: host=%d, arm=%d, wasm=%d | target-aware=%d | hdrs: host=%d, cross=%d, total=%d)",
                      #result, counts["host"], counts["arm"], counts["wasm"] or 0,
                      counts.cross_with_triple,
                      hdr_counts.host, hdr_counts.cross, total_hdrs)

            end, {dependfile = dependfile,
                  files = table.join(project.allfiles(), config.filepath()),
                  values = header_file_list})

            lockfile:close()
        end
    end)
