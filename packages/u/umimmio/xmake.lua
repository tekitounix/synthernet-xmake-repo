package("umimmio")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("UMI type-safe memory-mapped I/O abstraction library")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    add_urls("https://github.com/tekitounix/umi/releases/download/v$(version)/umimmio-$(version).tar.gz")
    add_versions("dev", "git:../../../../lib/umimmio")
    add_versions("0.2.1", "70a9c29fe2e8bd2e5139db76100ffd20f864a935506a101630e31c60cc5ca53c")

    on_install(function(package)
        os.cp("include", package:installdir())
    end)

    on_test(function(package)
        assert(package:check_cxxsnippets({test = [[
            #include <umimmio/mmio.hh>
            void test() {}
        ]]}, {configs = {languages = "c++23"}}))
    end)
package_end()
