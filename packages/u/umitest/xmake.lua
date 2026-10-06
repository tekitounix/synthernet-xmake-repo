package("umitest")
    set_homepage("https://github.com/tekitounix/umitest")
    set_description("Zero-macro lightweight test framework for C++23")
    set_license("MIT")

    set_kind("library", {headeronly = true})

    if os.getenv("UMI_SOURCE") then
        add_versions("dev", "dummy")
        add_versions("0.2.2", "dummy")
    else
        add_urls("https://github.com/tekitounix/umitest/releases/download/v$(version)/umitest-$(version).tar.gz")
        add_versions("0.2.2", "8263cef37e59b094811a167abaf1f6975a1c433052b464489756d21b3bff0a1f")
    end

    on_install(function(package)
        local env_root = os.getenv("UMI_SOURCE")
        if env_root and env_root ~= "" then
            local source = path.join(env_root, "packages", "support", "test")
            if os.isdir(path.join(source, "include")) then
                os.cp(path.join(source, "include"), package:installdir())
                return
            end
            raise("UMI_SOURCE does not contain packages/support/test: %s", env_root)
        end

        if os.isdir("include") then
            os.cp("include", package:installdir())
            return
        end
        local subdirs = os.dirs("umitest-*")
        if subdirs and #subdirs > 0 and os.isdir(path.join(subdirs[1], "include")) then
            os.cp(path.join(subdirs[1], "include"), package:installdir())
            return
        end
        raise("umitest source root not found")
    end)

    -- on_test: same rationale as umimmio (C++23 deducing-this consumer).
    -- Skip host-side test_snippet to avoid older host-GCC false-negatives.
package_end()
