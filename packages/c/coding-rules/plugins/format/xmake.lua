-- xmake format plugin
-- Formats all source files in the project using clang-format

task("format")
    set_category("plugin")
    set_description("Format source code using clang-format")
    
    on_run(function ()
        import("core.base.option")
        import("core.project.project")
        import("lib.detect.find_program")
        import("core.base.global")
        
        -- Find clang-format
        local clang_format = find_program("clang-format")
        if not clang_format then
            raise("clang-format not found. Please install clang-format to use this command.")
        end
        
        -- Get config file path
        local rule_dir = path.join(global.directory(), "rules", "coding")
        local config_dir = path.join(rule_dir, "configs")
        local format_config = path.join(config_dir, ".clang-format")
        
        -- Check if config exists
        if not os.isfile(format_config) then
            raise("coding-rules package not properly installed. Config file not found: " .. format_config)
        end
        
        -- Get target filter
        local target_name = option.get("target")
        
        -- Collect all files to format
        local files_to_format = {}
        local seen_files = {}
        
        -- Process each target
        for _, target in pairs(project.targets()) do
            if target_name and target:name() ~= target_name then
                goto continue
            end
            
            -- Add source files
            for _, file in ipairs(target:sourcefiles()) do
                if file:endswith(".cc") or file:endswith(".cpp") or 
                   file:endswith(".c") or file:endswith(".hh") or 
                   file:endswith(".hpp") or file:endswith(".h") then
                    if not seen_files[file] then
                        table.insert(files_to_format, file)
                        seen_files[file] = true
                    end
                end
            end
            
            -- Add header files from include directories
            for _, dir in ipairs(target:get("includedirs")) do
                if os.isdir(dir) then
                    for _, pattern in ipairs({"**.hh", "**.hpp", "**.h"}) do
                        local headers = os.files(path.join(dir, pattern))
                        for _, h in ipairs(headers) do
                            if not seen_files[h] then
                                table.insert(files_to_format, h)
                                seen_files[h] = true
                            end
                        end
                    end
                end
            end
            
            ::continue::
        end
        
        -- Also format files in the project root
        if not target_name then
            local project_files = {}
            for _, pattern in ipairs({"**.cc", "**.cpp", "**.c", "**.hh", "**.hpp", "**.h"}) do
                local files = os.files(path.join(os.projectdir(), pattern))
                for _, f in ipairs(files) do
                    -- Skip build directory and external dependencies
                    if not f:find("/build/") and not f:find("/.xmake/") and
                       not f:find("/packages/") and not f:find("/node_modules/") and
                       not f:find("/.ref/") then
                        if not seen_files[f] then
                            table.insert(files_to_format, f)
                            seen_files[f] = true
                        end
                    end
                end
            end
        end
        
        if #files_to_format == 0 then
            print("No files to format.")
            return
        end
        
        print("Formatting %d files...", #files_to_format)
        
        -- Format each file
        local formatted_count = 0
        for _, file in ipairs(files_to_format) do
            if option.get("verbose") then
                print("  Formatting: %s", file)
            end
            
            -- Check if file needs formatting first
            local _, errdata = os.iorunv(clang_format, {
                "--dry-run",
                "--Werror",
                "--style=file:" .. format_config,
                file
            })
            
            if errdata and #errdata > 0 then
                -- File needs formatting
                os.execv(clang_format, {
                    "-i",
                    "--style=file:" .. format_config,
                    file
                })
                formatted_count = formatted_count + 1
                print("  ✓ Formatted: %s", path.relative(file, os.projectdir()))
            end
        end
        
        if formatted_count > 0 then
            print("Formatted %d files.", formatted_count)
        else
            print("All files are already properly formatted.")
        end
    end)
    
    set_menu {
        usage = "xmake format [options]",
        description = "Format source code using clang-format",
        options = {
            {'t', "target", "kv", nil, "Format only the specified target"},
            {'v', "verbose", "k", nil, "Show verbose output"}
        }
    }