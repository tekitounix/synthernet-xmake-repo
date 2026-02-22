-- json_pretty.lua — Pretty-print JSON with 2-space indent.
--
-- xmake's json.encode() produces minified output with escaped slashes.
-- This module provides readable output for config files (.mcp.json, settings.json).
--
-- Usage:
--   import("core.base.json")
--   import("json_pretty", {rootdir = script_dir})
--   local text = json_pretty.encode(data)
--   io.writefile("config.json", text)

import("core.base.json")

-- Encode a Lua value as pretty-printed JSON.
-- Tables with sequential integer keys are treated as arrays.
function encode(val, _indent)
    _indent = _indent or 0
    local pad = string.rep("  ", _indent)
    local pad1 = string.rep("  ", _indent + 1)

    if type(val) ~= "table" then
        return json.encode(val)
    end

    -- Array: has sequential integer keys starting at 1
    if #val > 0 then
        local parts = {}
        for _, v in ipairs(val) do
            table.insert(parts, pad1 .. encode(v, _indent + 1))
        end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
    end

    -- Object: collect and sort string keys
    local keys = table.keys(val)
    if #keys == 0 then return "{}" end
    table.sort(keys)

    local parts = {}
    for _, k in ipairs(keys) do
        table.insert(parts, pad1 .. json.encode(k) .. ": " .. encode(val[k], _indent + 1))
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
end

-- Encode and unescape slashes for readability.
-- xmake's json.encode escapes "/" as "\/" — this undoes it.
function encode_clean(val)
    return encode(val):gsub("\\/", "/") .. "\n"
end
