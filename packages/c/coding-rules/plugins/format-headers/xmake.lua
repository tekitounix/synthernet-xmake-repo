-- xmake format-headers plugin
-- Reorders file header comments to match API_COMMENT_RULE §2.1.
--
-- Required order for .hh / .ipp files:
--   1. #pragma once
--   2. // SPDX-License-Identifier: <license>
--   3. // Copyright (c) <year>, <holder>
--   4. /// @file
--   5. /// @brief ... (with continuation lines)
--   6. /// @author ...
--   7. <blank line>
--   8. <rest of file>
--
-- Configuration: reads .header-order.lua from project root (optional).

task("format-headers")
    set_category("plugin")

    on_run(function ()
        import("core.base.option")

        local project_dir = os.projectdir()
        local dry_run = option.get("dry-run")
        local verbose = option.get("diagnosis")

        -- Load config from .header-order.lua (optional)
        -- Parsed with pattern matching (xmake sandbox blocks load/dofile).
        local config = {}
        local config_path = path.join(project_dir, ".header-order.lua")
        if os.isfile(config_path) then
            local text = io.readfile(config_path)
            -- Parse string value:  key = "value"
            local function parse_string(key)
                local val = text:match(key .. '%s*=%s*"([^"]*)"')
                return val
            end
            -- Parse boolean value:  key = true/false
            local function parse_bool(key)
                local val = text:match(key .. "%s*=%s*(%a+)")
                if val == "true" then return true end
                if val == "false" then return false end
                return nil
            end
            -- Parse string array:  key = {"a", "b", "c"}
            local function parse_string_array(key)
                local block = text:match(key .. "%s*=%s*{([^}]*)}")
                if not block then return nil end
                local arr = {}
                for item in block:gmatch('"([^"]*)"') do
                    table.insert(arr, item)
                end
                return arr
            end
            config.scan_dirs    = parse_string_array("scan_dirs")
            config.extensions   = parse_string_array("extensions")
            config.exclude      = parse_string_array("exclude")
            config.include_only = parse_bool("include_only")
            config.license      = parse_string("license")
            config.copyright    = parse_string("copyright")
        end

        local scan_dirs    = config.scan_dirs or {}
        local include_only = config.include_only
        if include_only == nil then include_only = true end
        local extensions   = config.extensions or {"hh", "ipp"}
        local excludes     = config.exclude or {"/_archive/"}

        -- Build glob patterns and collect files
        local dirs = #scan_dirs > 0 and scan_dirs or {""}
        local files = {}
        local seen = {}

        for _, dir in ipairs(dirs) do
            for _, ext in ipairs(extensions) do
                local base = dir ~= "" and path.join(project_dir, dir) or project_dir
                local pattern
                if include_only then
                    pattern = path.join("**", "include", "**", "*." .. ext)
                else
                    pattern = path.join("**", "*." .. ext)
                end
                local found = os.files(path.join(base, pattern))
                for _, f in ipairs(found) do
                    -- Check excludes
                    local excluded = false
                    for _, ex in ipairs(excludes) do
                        if f:find(ex, 1, true) then
                            excluded = true
                            break
                        end
                    end
                    if not excluded and not seen[f] then
                        table.insert(files, f)
                        seen[f] = true
                    end
                end
            end
        end
        table.sort(files)

        local total = #files
        local changed = 0

        if verbose then
            print("Scanning %d files...", total)
        end

        for _, filepath in ipairs(files) do
            local content = io.readfile(filepath)
            local lines = content:split("\n", {plain = true})

            -- Parse header block
            local pragma_line = nil
            local spdx_line = nil
            local copyright_line = nil
            local file_lines = {}
            local brief_lines = {}
            local author_lines = {}
            local header_end = 0

            local i = 1
            while i <= #lines do
                local line = lines[i]
                local stripped = line:trim()

                -- Blank lines in header block — skip
                if stripped == "" then
                    i = i + 1
                -- #pragma once
                elseif stripped == "#pragma once" then
                    pragma_line = line
                    i = i + 1
                -- SPDX
                elseif stripped:find("SPDX%-License%-Identifier", 1, false) then
                    spdx_line = line
                    i = i + 1
                -- Copyright
                elseif stripped:startswith("// Copyright") then
                    copyright_line = line
                    i = i + 1
                -- @file
                elseif stripped:startswith("/// @file") then
                    table.insert(file_lines, line)
                    i = i + 1
                -- @brief (may have continuation lines)
                elseif stripped:startswith("/// @brief") then
                    table.insert(brief_lines, line)
                    i = i + 1
                    -- Collect continuation lines (/// not starting with @)
                    while i <= #lines do
                        local next_stripped = lines[i]:trim()
                        if next_stripped:startswith("///") and not next_stripped:startswith("/// @") then
                            table.insert(brief_lines, lines[i])
                            i = i + 1
                        elseif next_stripped == "///" then
                            table.insert(brief_lines, lines[i])
                            i = i + 1
                        else
                            break
                        end
                    end
                -- @author
                elseif stripped:startswith("/// @author") then
                    table.insert(author_lines, line)
                    i = i + 1
                -- Other comment lines (skip)
                elseif stripped:startswith("//") then
                    i = i + 1
                -- Non-header line found — stop
                else
                    break
                end
            end
            header_end = i

            -- Skip if no pragma or no SPDX (nothing to reorder)
            if not pragma_line or not spdx_line then
                goto continue
            end

            -- Build correct order
            local new_header = {}
            table.insert(new_header, pragma_line)
            table.insert(new_header, "")
            table.insert(new_header, spdx_line)
            if copyright_line then
                table.insert(new_header, copyright_line)
            end
            for _, fl in ipairs(file_lines) do
                table.insert(new_header, fl)
            end
            for _, bl in ipairs(brief_lines) do
                table.insert(new_header, bl)
            end
            for _, al in ipairs(author_lines) do
                table.insert(new_header, al)
            end

            -- Compare old vs new (ignoring blank lines)
            local old_nonblank = {}
            for j = 1, header_end - 1 do
                if lines[j]:trim() ~= "" then
                    table.insert(old_nonblank, lines[j]:rtrim())
                end
            end
            local new_nonblank = {}
            for _, l in ipairs(new_header) do
                if l:trim() ~= "" then
                    table.insert(new_nonblank, l:rtrim())
                end
            end

            if table.concat(old_nonblank) == table.concat(new_nonblank) then
                goto continue
            end

            -- Reconstruct file: header + blank line + rest
            local rest = {}
            for j = header_end, #lines do
                table.insert(rest, lines[j])
            end
            -- Ensure blank line between header and body
            if #rest > 0 and rest[1]:trim() ~= "" then
                table.insert(rest, 1, "")
            end

            local new_content = table.concat(new_header, "\n") .. "\n" .. table.concat(rest, "\n")
            -- Normalize multiple blank lines (3+ newlines → 2)
            new_content = new_content:gsub("\n\n\n+", "\n\n")

            if new_content ~= content then
                if dry_run then
                    print("  would fix: %s", path.relative(filepath, project_dir))
                else
                    io.writefile(filepath, new_content)
                    print("  fixed: %s", path.relative(filepath, project_dir))
                end
                changed = changed + 1
            end

            ::continue::
        end

        print("")
        if dry_run then
            print("Total: %d files checked, %d files would change", total, changed)
        else
            print("Total: %d files checked, %d files fixed", total, changed)
        end
    end)

    set_menu {
        usage = "xmake format-headers [options]",
        description = "Reorder file header comments to match API_COMMENT_RULE §2.1",
        options = {
            {nil, "dry-run", "k", nil, "Show what would change without modifying files"},
        }
    }
