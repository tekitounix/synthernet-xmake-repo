-- xmake coding-format plugin (project-root config reference)
-- Uses .clang-format from os.projectdir() as the single source of truth.
-- Scan directories default to project root; excludes /build/ and /.xmake/ only.

task("coding-format")
    set_category("plugin")

    on_run(function ()
        import("core.base.option")
        import("core.base.global")
        import("lib.detect.find_program")

        local clang_format = find_program("clang-format")
        if not clang_format then
            raise("clang-format not found. Please install clang-format.")
        end

        -- Project root .clang-format is the single source of truth
        local project_dir = os.projectdir()
        local format_config = path.join(project_dir, ".clang-format")
        if not os.isfile(format_config) then
            raise(".clang-format not found in project root: " .. project_dir)
        end

        -- Load shared file collector
        local script_dir = path.join(global.directory(), "rules", "coding", "scripts")
        local collector = import("file_collector", {rootdir = script_dir})
        collector.init()

        local dry_run = option.get("dry-run")
        local files_filter = option.get("input")
        local target_name = option.get("target")

        -- Collect files
        local files_to_format
        if files_filter then
            files_to_format = collector.from_explicit(files_filter, project_dir)
            -- Filter to only existing files
            local existing = {}
            for _, f in ipairs(files_to_format) do
                if os.isfile(f) then
                    table.insert(existing, f)
                end
            end
            files_to_format = existing
        else
            files_to_format = collector.from_scan(project_dir, {
                extensions = collector.all_extensions,
                target = target_name,
            })
        end

        if #files_to_format == 0 then
            print("No files to format.")
            return
        end

        local formatted_count = 0

        for _, file in ipairs(files_to_format) do
            -- Check if file needs formatting using --dry-run --Werror
            local _, errdata = os.iorunv(clang_format, {
                "--dry-run", "--Werror",
                "--style=file:" .. format_config, file
            })

            if errdata and #errdata > 0 then
                if dry_run then
                    print("  Needs formatting: %s", path.relative(file, project_dir))
                    formatted_count = formatted_count + 1
                else
                    os.execv(clang_format, {"-i", "--style=file:" .. format_config, file})
                    formatted_count = formatted_count + 1
                    if option.get("diagnosis") then
                        print("  Formatted: %s", path.relative(file, project_dir))
                    end
                end
            end
        end

        if formatted_count > 0 then
            if dry_run then
                print("%d file(s) need formatting.", formatted_count)
                os.exit(1)  -- Non-zero for CI usage
            else
                print("Formatted %d file(s).", formatted_count)
            end
        else
            print("All %d files are already properly formatted.", #files_to_format)
        end
    end)

    set_menu {
        usage = "xmake coding-format [options]",
        description = "Format source code using clang-format",
        options = {
            {'t', "target",  "kv", nil, "Format only the specified target"},
            {'i', "input",   "kv", nil, "Comma-separated file paths to format"},
            {nil, "dry-run", "k",  nil, "Check only, do not modify files"},
        }
    }
