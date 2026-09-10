package("umipal")
    set_homepage("https://github.com/tekitounix/umipal")
    set_description("Type-safe header-only C++23 Peripheral Access Layer (PAL) generator for ARM Cortex-M MCUs")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    if os.getenv("UMIPAL_SOURCE") then
        add_versions("0.0.0-dev", "dummy")
        add_versions("1.0.0", "dummy")
        add_versions("1.1.0", "dummy")
        add_versions("2.3.0", "dummy")
    else
        add_urls("https://github.com/tekitounix/umipal/releases/download/v$(version)/umipal-$(version).tar.gz")
        add_versions("1.0.0", "e4e12ee2ed470b3bce6581f51e2156eeca3277d3183655166964d15bf568c39e")
        add_versions("1.1.0", "346f41ff20cd38ecdede64428cbed48c8223e88806d0d395737b6e7715717a25")
        add_versions("2.3.0", "65fea26219e62e483277cce3bd64ab26456cd272970b4de23173529b7ced0b63")
    end

    add_deps("umimmio")

    on_install(function(package)
        local env_root = os.getenv("UMIPAL_SOURCE")
        if env_root and env_root ~= "" then
            local source = env_root
            if os.isdir(path.join(source, "include")) then
                os.cp(path.join(source, "include"), package:installdir())
                if os.isdir(path.join(source, "share")) then
                    os.cp(path.join(source, "share"), package:installdir())
                end
                return
            end
            raise("UMIPAL_SOURCE does not contain an umipal source tree with include/: %s", env_root)
        end

        if os.isdir("include") then
            os.cp("include", package:installdir())
            if os.isdir("share") then
                os.cp("share", package:installdir())
            end
            return
        end
        local subdirs = os.dirs("umipal-*")
        if subdirs and #subdirs > 0 and os.isdir(path.join(subdirs[1], "include")) then
            os.cp(path.join(subdirs[1], "include"), package:installdir())
            if os.isdir(path.join(subdirs[1], "share")) then
                os.cp(path.join(subdirs[1], "share"), package:installdir())
            end
            return
        end
        raise("umipal source root not found")
    end)

    -- on_test omitted: umipal headers require C++23 deducing-this (umimmio
    -- dependency) and ARM cross-toolchain, so host-side test gives no signal.
    -- Coverage lives upstream in tekitounix/umipal CI (cargo / xmake / Renode
    -- / hardware gates) and downstream in firmware projects that consume
    -- this package via embedded toolchains.
package_end()
