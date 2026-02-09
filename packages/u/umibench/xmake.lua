package("umibench")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("UMI cross-target micro-benchmark library")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    add_urls("https://github.com/tekitounix/umi/releases/download/v$(version)/umibench-$(version).tar.gz")
    add_versions("dev", "git:../../../../lib/umibench")

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
        os.cp("include", package:installdir())
        os.cp("platforms", package:installdir())
    end)

    on_test(function(package)
        assert(package:check_cxxsnippets({test = [[
            #include <umibench/bench.hh>
            void test() {}
        ]]}, {configs = {languages = "c++23"}}))
    end)
package_end()
