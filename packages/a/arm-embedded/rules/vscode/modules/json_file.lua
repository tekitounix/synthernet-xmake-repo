-- JSON file utilities for VSCode configuration generation.
-- Provides load-filter-save operations that preserve user-defined entries
-- while allowing managed entries to be regenerated.

import("core.base.json")

-- Load a JSON file and filter out managed entries, returning user entries only.
--
-- @param filepath     Path to the JSON file
-- @param array_key    Key of the array in the JSON root (e.g. "tasks", "configurations")
-- @param is_managed   Function(name) -> bool, returns true for managed entries
-- @param name_field   Field name used to identify entries (e.g. "label", "name")
-- @return table       The loaded JSON structure with only user entries in the array
function load_and_filter(filepath, array_key, is_managed, name_field)
    local default_versions = {
        tasks = "2.0.0",
        configurations = "0.2.0"
    }
    local result = {
        version = default_versions[array_key] or "2.0.0",
        [array_key] = {}
    }

    if not os.isfile(filepath) then
        return result
    end

    local existing = try { function() return json.loadfile(filepath) end }
    if not existing then
        return result
    end

    result.version = existing.version or result.version

    if existing[array_key] then
        for _, entry in ipairs(existing[array_key]) do
            local name = entry[name_field]
            if name and not is_managed(name) then
                table.insert(result[array_key], entry)
            end
        end
    end

    return result
end

-- Encode a Lua value as a pretty-printed JSON string.
-- Produces human-readable output with 2-space indentation.
local function pretty_encode(value, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local pad1 = string.rep("  ", indent + 1)
    local t = type(value)

    if value == nil then
        return "null"
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "number" then
        if value == math.floor(value) then
            return string.format("%d", value)
        end
        return tostring(value)
    elseif t == "string" then
        -- Escape special characters
        local escaped = value:gsub('\\', '\\\\'):gsub('"', '\\"')
                             :gsub('\n', '\\n'):gsub('\r', '\\r')
                             :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Detect array vs object: array if all keys are consecutive integers 1..n
        local is_array = true
        local n = #value
        for k, _ in pairs(value) do
            if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
                is_array = false
                break
            end
        end
        -- Empty table: check if json module marked it
        if n == 0 then
            local has_keys = false
            for _ in pairs(value) do has_keys = true; break end
            if not has_keys then
                -- Could be empty array or empty object — default to empty array
                -- unless it was loaded from JSON as object
                return "[]"
            end
        end

        if is_array then
            if n == 0 then return "[]" end
            local items = {}
            for i = 1, n do
                table.insert(items, pad1 .. pretty_encode(value[i], indent + 1))
            end
            return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
        else
            -- Object: sort keys for deterministic output
            local keys = {}
            for k, _ in pairs(value) do
                table.insert(keys, k)
            end
            table.sort(keys)
            if #keys == 0 then return "{}" end
            local items = {}
            for _, k in ipairs(keys) do
                local encoded_key = '"' .. tostring(k) .. '"'
                local encoded_val = pretty_encode(value[k], indent + 1)
                table.insert(items, pad1 .. encoded_key .. ": " .. encoded_val)
            end
            return "{\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "}"
        end
    end
    return tostring(value)
end

-- Save a table as a pretty-printed JSON file, creating parent directories if needed.
--
-- @param filepath  Path to write
-- @param data      Table to serialize
function save(filepath, data)
    os.mkdir(path.directory(filepath))
    local content = pretty_encode(data, 0) .. "\n"
    io.writefile(filepath, content)
end
