package("umibench")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("UMI cross-target micro-benchmark library")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    if os.getenv("UMI_SOURCE") then
        add_versions("0.0.0-dev", "dummy")
        add_versions("0.3.1", "dummy")
    else
        add_urls("https://github.com/tekitounix/synthernet-xmake-repo/releases/download/umibench-v$(version)/umibench-$(version).tar.gz")
        add_versions("0.3.1", "d56e124f5ef1448485f52c837857d4af5cd40c8080559ce4964e8fbd0585ee6e")
    end

    add_configs("backend", {
        description = "Target backend",
        default = "host",
        values = {"host", "wasm", "embedded"}
    })

    on_load(function(package)
        if package:config("backend") == "embedded" then
            package:add("deps", "arm-embedded")
            package:add("deps", "umimmio")
        end
    end)

    on_install(function(package)
        local env_root = os.getenv("UMI_SOURCE")
        if env_root and env_root ~= "" then
            local source = path.join(env_root, "packages", "support", "bench")
            if os.isdir(path.join(source, "include")) then
                os.cp(path.join(source, "include"), package:installdir())
                if os.isdir(path.join(source, "platforms")) then
                    os.cp(path.join(source, "platforms"), package:installdir())
                end
                return
            end
            raise("UMI_SOURCE does not contain packages/support/bench: %s", env_root)
        end

        if os.isdir("include") then
            os.cp("include", package:installdir())
            if os.isdir("platforms") then
                os.cp("platforms", package:installdir())
            end
            return
        end
        local subdirs = os.dirs("umibench-*")
        if subdirs and #subdirs > 0 and os.isdir(path.join(subdirs[1], "include")) then
            os.cp(path.join(subdirs[1], "include"), package:installdir())
            if os.isdir(path.join(subdirs[1], "platforms")) then
                os.cp(path.join(subdirs[1], "platforms"), package:installdir())
            end
            return
        end
        raise("umibench source root not found")
    end)

    on_test(function(package)
        assert(package:check_cxxsnippets({test = [[
            #include <umibench/bench.hh>
            void test() {}
        ]]}, {configs = {languages = "c++23"}}))
    end)
package_end()
