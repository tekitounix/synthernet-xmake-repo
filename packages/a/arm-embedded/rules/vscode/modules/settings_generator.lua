-- Settings.json generator for VSCode clangd integration.
-- Manages clangd.arguments (including --query-driver for cross-compilers)
-- while preserving all other user-defined settings.

import("core.base.json")
import("json_file")

-- Generate or update .vscode/settings.json.
--
-- @param vscode_dir        Path to .vscode directory
-- @param embedded_targets  Array of { compiler_path = "...", ... }
function generate(vscode_dir, embedded_targets)
    local settings_file = path.join(vscode_dir, "settings.json")

    -- Collect unique compiler paths as query drivers
    local query_drivers_set = {}
    local query_drivers = {}
    for _, target_info in ipairs(embedded_targets) do
        local driver = target_info.compiler_path
        if driver and not query_drivers_set[driver] then
            query_drivers_set[driver] = true
            table.insert(query_drivers, driver)
        end
    end
    table.sort(query_drivers)

    -- Build clangd arguments
    local clangd_args = {
        "--log=error",
        "--clang-tidy",
        "--header-insertion=never",
        "--all-scopes-completion"
    }
    if #query_drivers > 0 then
        table.insert(clangd_args, "--query-driver=" .. table.concat(query_drivers, ","))
    end

    -- Read existing settings and check if update is needed
    local settings = {}
    local needs_update = true
    if os.isfile(settings_file) then
        local existing = try { function() return json.loadfile(settings_file) end }
        if existing then
            settings = existing
            -- Compare existing clangd.arguments with new ones
            if settings["clangd.arguments"] and type(settings["clangd.arguments"]) == "table" then
                local function normalize_args(args)
                    local sorted = {}
                    for _, arg in ipairs(args) do
                        table.insert(sorted, arg)
                    end
                    table.sort(sorted)
                    return table.concat(sorted, "|")
                end
                if normalize_args(settings["clangd.arguments"]) == normalize_args(clangd_args) then
                    needs_update = false
                end
            end
        end
    end

    if not needs_update then
        return
    end

    -- Update managed keys
    settings["clangd.arguments"] = clangd_args

    -- Remove legacy clang-format.style setting
    -- (.clang-format at project root is auto-detected by both clangd and the extension)
    settings["clang-format.style"] = nil

    -- Write with pretty-printed JSON
    json_file.save(settings_file, settings)
    print("settings.json updated!")
end
