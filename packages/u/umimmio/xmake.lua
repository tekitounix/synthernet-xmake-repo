package("umimmio")
    set_homepage("https://github.com/tekitounix/umimmio")
    set_description("Type-safe memory-mapped I/O abstraction library")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    if os.getenv("UMI_SOURCE") then
        add_versions("0.0.0-dev", "dummy")
        add_versions("0.3.0", "dummy")
    else
        add_urls("https://github.com/tekitounix/umimmio/releases/download/v$(version)/umimmio-$(version).tar.gz")
        add_versions("0.3.0", "fed75d34aae34c2993533bb81a3f85ccf65b4024a0dc12bca4d14b53e25812f4")
    end

    on_install(function(package)
        local env_root = os.getenv("UMI_SOURCE")
        if env_root and env_root ~= "" then
            local source = path.join(env_root, "packages", "primitive", "mmio")
            if os.isdir(path.join(source, "include")) then
                os.cp(path.join(source, "include"), package:installdir())
                return
            end
            raise("UMI_SOURCE does not contain packages/primitive/mmio: %s", env_root)
        end

        if os.isdir("include") then
            os.cp("include", package:installdir())
            return
        end
        local subdirs = os.dirs("umimmio-*")
        if subdirs and #subdirs > 0 and os.isdir(path.join(subdirs[1], "include")) then
            os.cp(path.join(subdirs[1], "include"), package:installdir())
            return
        end
        raise("umimmio source root not found")
    end)

    -- on_test: umimmio uses C++23 deducing-this (`auto f(this Self&...)`),
    -- which requires GCC 14+ / Clang 18+. CI hosts often ship older GCC,
    -- and this header-only package is consumed (and tested) downstream by
    -- umipal/umiport via embedded toolchains that pin a recent compiler.
    -- Run-time host-side tests would only verify the host compiler version,
    -- not the package itself, so they're intentionally omitted.
package_end()
