package("umitest")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("UMI zero-macro lightweight test framework for C++23")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    add_urls("https://github.com/tekitounix/umi/releases/download/v$(version)/umitest-$(version).tar.gz")
    add_versions("dev", "git:../../../../lib/umitest")

    on_install(function(package)
        os.cp("include", package:installdir())
    end)

    on_test(function(package)
        assert(package:check_cxxsnippets({test = [[
            #include <umitest/test.hh>
            void test() {
                umi::test::Suite s("pkg_test");
            }
        ]]}, {configs = {languages = "c++23"}}))
    end)
package_end()
