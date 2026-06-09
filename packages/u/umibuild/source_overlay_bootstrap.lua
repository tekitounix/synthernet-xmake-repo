-- Source-overlay bootstrap for consumers that need UMI xmake DSL helpers
-- before target parsing. The `umibuild` package on_load hook installs rules
-- for ordinary `add_rules("umi.target")` use, but functions such as
-- `umi_app()` and `umi_app_matrix()` must exist while xmake parses the
-- consumer project. Until a released umibuild archive exposes these files,
-- source overlay resolves them from UMI_SOURCE through the provider repo.

local function source_path(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if path.is_absolute(value) then
        return value
    end
    return path.join(os.projectdir(), value)
end

local function fail(message)
    error(message, 2)
end

local umi_source = source_path(os.getenv("UMI_SOURCE"))
if umi_source == nil then
    fail("umibuild source-overlay bootstrap requires UMI_SOURCE")
end

local umibuild_root = path.join(umi_source, "build-rules", "umibuild")
if not os.isdir(umibuild_root) then
    fail("UMI_SOURCE does not contain build-rules/umibuild: " .. umi_source)
end

includes(path.join(umibuild_root, "modules", "app_composer.lua"))
includes(path.join(umibuild_root, "rules", "umi.target", "xmake.lua"))
includes(path.join(umibuild_root, "rules", "embedded.compdb", "xmake.lua"))
includes(path.join(umibuild_root, "rules", "embedded.vscode", "xmake.lua"))
includes(path.join(umibuild_root, "rules", "coding.style", "xmake.lua"))
includes(path.join(umibuild_root, "rules", "coding.test", "xmake.lua"))
