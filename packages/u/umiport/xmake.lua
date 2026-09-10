package("umiport")
    set_homepage("https://github.com/tekitounix/umi")
    set_description("UMI shared platform infrastructure (STM32F4 startup, linker, UART)")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    if os.getenv("UMI_SOURCE") then
        add_versions("0.0.0-dev", "dummy")
        add_versions("0.3.1", "dummy")
    else
        add_urls("https://github.com/tekitounix/synthernet-xmake-repo/releases/download/umi-port-v$(version)/umi-port-$(version).tar.gz")
        add_versions("0.3.1", "f28c16f40da4336a538cc6a794a4ee25d6cecc31b28a3a7510b1dc2fdc1f936d")
    end

    add_deps("umihal")
    add_deps("umimmio")
    add_deps("umi.contract.audio")
    add_deps("umi.contract.application")
    add_deps("umi.contract.control")
    add_deps("umi.primitive.base_types")
    add_deps("umidi")
    add_deps("umipal")
    add_deps("umiutil")

    on_install(function(package)
        local function copy_optional_bootloader_include(source)
            local dir = path.join(source, "bootloader", "include")
            if os.isdir(dir) then
                os.cp(path.join(dir, "umiport"), path.join(package:installdir(), "include"))
            end
        end

        local env_root = os.getenv("UMI_SOURCE")
        if env_root and env_root ~= "" then
            local source = path.join(env_root, "packages", "platform", "port")
            if os.isdir(path.join(source, "include")) then
                os.cp(path.join(source, "include"), package:installdir())
                copy_optional_bootloader_include(source)
                if os.isdir(path.join(source, "src")) then
                    os.cp(path.join(source, "src"), package:installdir())
                end
                if os.isdir(path.join(source, "tests", "renode")) then
                    os.cp(path.join(source, "tests", "renode"), path.join(package:installdir(), "renode"))
                end
                return
            end
            raise("UMI_SOURCE does not contain packages/platform/port: %s", env_root)
        end

        if os.isdir("include") then
            os.cp("include", package:installdir())
            copy_optional_bootloader_include(os.curdir())
            if os.isdir("src") then
                os.cp("src", package:installdir())
            end
            if os.isdir("renode") then
                os.cp("renode", package:installdir())
            end
            return
        end
        local subdirs = os.dirs("umiport-*")
        if subdirs and #subdirs > 0 and os.isdir(path.join(subdirs[1], "include")) then
            os.cp(path.join(subdirs[1], "include"), package:installdir())
            copy_optional_bootloader_include(subdirs[1])
            if os.isdir(path.join(subdirs[1], "src")) then
                os.cp(path.join(subdirs[1], "src"), package:installdir())
            end
            if os.isdir(path.join(subdirs[1], "renode")) then
                os.cp(path.join(subdirs[1], "renode"), package:installdir())
            end
            return
        end
        raise("umiport source root not found")
    end)

    on_test(function(package)
        assert(os.isfile(path.join(package:installdir(), "include", "umiport", "port.hh")))
        assert(os.isfile(path.join(package:installdir(), "include", "umiport", "bootloader", "arm_cortex_m_dispatcher.hh")))
        assert(os.isfile(path.join(package:installdir(), "src", "common", "syscall_stubs.cc")))
        assert(os.isfile(path.join(package:installdir(), "renode", "stm32f4_test.repl")))
    end)
package_end()
