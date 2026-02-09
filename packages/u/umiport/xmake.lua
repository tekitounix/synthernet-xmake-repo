package("umiport")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("UMI shared platform infrastructure (STM32F4 startup, linker, UART)")
    set_license("MIT")

    set_kind("library", {headeronly = false})

    add_versions("dev", "git:../../../../lib/umiport")

    add_deps("umimmio")

    on_install(function(package)
        os.cp("include", package:installdir())
        os.cp("src", package:installdir())
        os.cp("renode", package:installdir())
    end)

    on_test(function(package)
        assert(os.isfile(path.join(package:installdir(), "src", "stm32f4", "startup.cc")))
        assert(os.isfile(path.join(package:installdir(), "renode", "stm32f4_test.repl")))
    end)
package_end()
