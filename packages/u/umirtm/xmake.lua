package("umirtm")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("UMI SEGGER RTT-compatible monitor library")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    add_urls("https://github.com/tekitounix/umi/releases/download/v$(version)/umirtm-$(version).tar.gz")
    add_versions("dev", "git:../../../../lib/umirtm")

    on_install(function(package)
        os.cp("include", package:installdir())
    end)

    on_test(function(package)
        assert(package:check_cxxsnippets({test = [[
            #include <umirtm/rtm.hh>
            void test() {}
        ]]}, {configs = {languages = "c++23"}}))
    end)
package_end()
