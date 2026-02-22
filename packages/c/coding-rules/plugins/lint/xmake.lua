-- xmake lint plugin (compdb-based)
-- Uses compile_commands.json for accurate compilation flags.
-- Supports: --target, --input, --changed, --json, --fix, --checks

task("lint")
    set_category("plugin")

    on_run(function ()
        import("core.base.option")
        import("lib.detect.find_program")

        -- Find clang-tidy
        local clang_tidy = find_program("clang-tidy")
        if not clang_tidy then
            raise("clang-tidy not found. Please install clang-tidy.")
        end

        -- Find compile_commands.json (正本: build/compdb/)
        local compdb_path = nil
        local search_paths = {
            path.join(os.projectdir(), "build", "compdb", "compile_commands.json"),
            path.join(os.projectdir(), "compile_commands.json"),
        }
        for _, p in ipairs(search_paths) do
            if os.isfile(p) then
                compdb_path = p
                break
            end
        end
        if not compdb_path then
            raise("compile_commands.json not found. Run 'xmake build' first.")
        end
        local compdb_dir = path.directory(compdb_path)

        -- Load compdb entries
        local compdb_data = io.readfile(compdb_path)
        local entries = {}
        -- Parse JSON manually (xmake json module)
        import("core.base.json")
        entries = json.decode(compdb_data)

        -- Build file set from compdb
        local compdb_files = {}
        for _, entry in ipairs(entries) do
            local file = entry.file
            if file then
                compdb_files[file] = true
            end
        end

        -- Get options
        local target_filter = option.get("target")
        local files_filter = option.get("input")
        local changed_only = option.get("changed")
        local json_output = option.get("json")
        local fix_mode = option.get("fix")
        local checks = option.get("checks")

        -- Collect files to check
        local files_to_check = {}
        local seen = {}

        if files_filter then
            -- Explicit file list (comma-separated)
            for file in files_filter:gmatch("[^,]+") do
                file = file:match("^%s*(.-)%s*$")  -- trim
                if not path.is_absolute(file) then
                    file = path.join(os.projectdir(), file)
                end
                if not seen[file] then
                    table.insert(files_to_check, file)
                    seen[file] = true
                end
            end
        elseif changed_only then
            -- Git diff based (no hardcoded path filters)
            import("core.base.global")
            local script_dir = path.join(global.directory(), "rules", "coding", "scripts")
            local collector = import("file_collector", {rootdir = script_dir})
            collector.init()
            local changed = collector.from_git_changed(os.projectdir(), {
                extensions = collector.source_extensions,
                filter_fn = function(f) return compdb_files[f] end,
            })
            for _, abs in ipairs(changed) do
                if not seen[abs] then
                    table.insert(files_to_check, abs)
                    seen[abs] = true
                end
            end
        elseif target_filter then
            -- Filter entries by target source directory pattern
            for _, entry in ipairs(entries) do
                local file = entry.file
                if file and file:find(target_filter, 1, true) then
                    if not seen[file] then
                        table.insert(files_to_check, file)
                        seen[file] = true
                    end
                end
            end
        else
            -- All files in compdb
            for _, entry in ipairs(entries) do
                local file = entry.file
                if file and (file:endswith(".cc") or file:endswith(".cpp") or file:endswith(".c")) then
                    if not seen[file] then
                        table.insert(files_to_check, file)
                        seen[file] = true
                    end
                end
            end
        end

        if #files_to_check == 0 then
            if json_output then
                print('{"success":true,"total_warnings":0,"total_errors":0,"files":[]}')
            else
                print("No files to check.")
            end
            return
        end

        if not json_output then
            print("Checking %d files with clang-tidy (compdb: %s)...", #files_to_check, compdb_path)
        end

        -- Run clang-tidy per file
        local results = {success = true, total_warnings = 0, total_errors = 0, files = {}}

        for _, file in ipairs(files_to_check) do
            if option.get("diagnosis") and not json_output then
                print("  Checking: %s", file)
            end

            local args = {file, "-p", compdb_dir}

            -- Use project root .clang-tidy by default
            local tidy_config = path.join(os.projectdir(), ".clang-tidy")
            if os.isfile(tidy_config) then
                args = table.join(args, {"--config-file=" .. tidy_config})
            end

            if checks then
                table.insert(args, "--checks=" .. checks)
            end
            if fix_mode then
                table.insert(args, "--fix")
            end
            if not option.get("diagnosis") and not json_output then
                table.insert(args, "--quiet")
            end

            local outdata, errdata = os.iorunv(clang_tidy, args)
            local combined = (outdata or "") .. "\n" .. (errdata or "")

            -- Parse diagnostics
            local file_result = {file = path.relative(file, os.projectdir()), diagnostics = {}}
            for line in combined:gmatch("[^\r\n]+") do
                local f, ln, col, sev, msg, check =
                    line:match("^(.+):(%d+):(%d+): (%w+): (.+) %[(.+)%]$")
                if sev == "warning" then
                    results.total_warnings = results.total_warnings + 1
                    table.insert(file_result.diagnostics, {
                        line = tonumber(ln), column = tonumber(col),
                        severity = sev, check = check, message = msg
                    })
                elseif sev == "error" then
                    results.total_errors = results.total_errors + 1
                    results.success = false
                    table.insert(file_result.diagnostics, {
                        line = tonumber(ln), column = tonumber(col),
                        severity = sev, check = check, message = msg
                    })
                end
            end

            if #file_result.diagnostics > 0 then
                table.insert(results.files, file_result)
                if not json_output then
                    print("  Issues in: %s (%d)", file_result.file, #file_result.diagnostics)
                    for _, d in ipairs(file_result.diagnostics) do
                        print("    %s:%d:%d %s: %s [%s]",
                              file_result.file, d.line, d.column, d.severity, d.message, d.check)
                    end
                end
            end
        end

        if json_output then
            import("core.base.json")
            print(json.encode(results))
        else
            print("")
            if results.total_warnings == 0 and results.total_errors == 0 then
                print("No issues found in %d files.", #files_to_check)
            else
                print("Found %d warning(s), %d error(s) in %d file(s).",
                      results.total_warnings, results.total_errors, #results.files)
            end
        end
    end)

    set_menu {
        usage = "xmake lint [options]",
        description = "Run clang-tidy using compile_commands.json",
        options = {
            {'t', "target",  "kv", nil,   "Filter by target name pattern"},
            {'i', "input",   "kv", nil,   "Comma-separated file paths to check"},
            {nil, "changed", "k",  nil,   "Check only git-changed files"},
            {nil, "json",    "k",  nil,   "Output structured JSON (for MCP)"},
            {nil, "fix",     "k",  nil,   "Attempt to auto-fix issues"},
            {'c', "checks",  "kv", nil,   "Override clang-tidy checks"},
        }
    }