local function joined(root, segments)
    local result = root
    for _, segment in ipairs(segments) do
        result = path.join(result, segment)
    end
    return result
end

local function fail(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        msg = string.format(fmt, ...)
    end
    error(msg, 2)
end

function umi_source_overlay_package(name, segments, opts)
    opts = opts or {}
    local release = opts.release or {}
    local release_versions = release.versions or {}

    package(name)
        set_homepage("https://github.com/tekitounix/umi")
        set_description(opts.description or ("UMI source-overlay package: " .. name))
        set_license("MIT")

        if opts.headeronly == false then
            set_kind("library")
        else
            set_kind("library", {headeronly = true})
        end

        if os.getenv("UMI_SOURCE") then
            add_versions("dev", "dummy")
            for version, _sha in pairs(release_versions) do
                add_versions(version, "dummy")
            end
        elseif release.repo and release.artifact and release.tag_prefix then
            add_urls(
                "https://github.com/" .. release.repo ..
                "/releases/download/" .. release.tag_prefix ..
                "$(version)/" .. release.artifact .. "-$(version).tar.gz")
            for version, sha in pairs(release_versions) do
                add_versions(version, sha)
            end
        end

        for _, dep in ipairs(opts.deps or {}) do
            add_deps(dep)
        end

        on_install(function(package)
            local function package_source_root()
                local env_root = os.getenv("UMI_SOURCE")
                if env_root and env_root ~= "" then
                    local source = joined(env_root, segments)
                    for _, dir_name in ipairs(opts.copy_dirs or {"include"}) do
                        if os.isdir(path.join(source, dir_name)) then
                            return source
                        end
                    end
                    fail("UMI_SOURCE does not contain %s: %s", table.concat(segments, "/"), env_root)
                end

                for _, dir_name in ipairs(opts.copy_dirs or {"include"}) do
                    if os.isdir(dir_name) then
                        return os.curdir()
                    end
                end
                if release.artifact then
                    local subdirs = os.dirs(release.artifact .. "-*")
                    for _, subdir in ipairs(subdirs or {}) do
                        for _, dir_name in ipairs(opts.copy_dirs or {"include"}) do
                            if os.isdir(path.join(subdir, dir_name)) then
                                return subdir
                            end
                        end
                    end
                end
                fail("%s source root not found", name)
            end

            local source = package_source_root()
            local copied = false
            for _, dir_name in ipairs(opts.copy_dirs or {"include"}) do
                local dir = path.join(source, dir_name)
                if os.isdir(dir) then
                    os.cp(dir, package:installdir())
                    copied = true
                end
            end
            for _, file_name in ipairs(opts.copy_files or {}) do
                local file = path.join(source, file_name)
                if os.isfile(file) then
                    os.cp(file, path.join(package:installdir(), file_name))
                    copied = true
                end
            end
            if not copied then
                fail("%s install payload not found", name)
            end
        end)

        on_test(function(package)
            for _, file_name in ipairs(opts.test_files or {}) do
                assert(os.isfile(path.join(package:installdir(), file_name)))
            end
            local main_header = opts.main_header
            if main_header then
                assert(os.isfile(path.join(package:installdir(), "include", main_header)))
            end
        end)
    package_end()
end
