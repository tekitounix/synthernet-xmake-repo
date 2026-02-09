package("renode")

    set_kind("binary")
    set_homepage("https://renode.io/")
    set_description("Open source simulation framework for embedded systems")

    if is_host("linux") then
        if os.arch():find("arm64") then
            add_urls("https://github.com/renode/renode/releases/download/v$(version)/renode-$(version).linux-arm64-portable-dotnet.tar.gz")
            add_versions("1.16.0", "449e4add705c6c8282facbe36cdb61755c86db6d3c7dd056fcd82f5ec4e4999e")
        else
            add_urls("https://github.com/renode/renode/releases/download/v$(version)/renode-$(version).linux-portable-dotnet.tar.gz")
            add_versions("1.16.0", "e676e4bfbafc4be6a2ee074a52d2e72ca0dc47433447839e47a160c42a3943cc")
        end
    elseif is_host("windows") then
        add_urls("https://github.com/renode/renode/releases/download/v$(version)/renode-$(version).windows-portable-dotnet.zip")
        add_versions("1.16.0", "3aff885fbc6cae0f91a2bca5bca7be4f3107682b6d52f0e776fdd013044e58d6")
    elseif is_host("macosx") then
        add_urls("https://github.com/renode/renode/releases/download/v$(version)/renode-$(version)-dotnet.osx-arm64-portable.dmg")
        add_versions("1.16.0", "93e1037c16cabf67fbd345ca8d7a30182418aa006e0b993e258bcd09df81ba21")
    end

    on_fetch(function (package, opt)
        if os.isdir(package:installdir()) then
            local bin = path.join(package:installdir(), "bin", "renode")
            if is_host("windows") then
                bin = path.join(package:installdir(), "bin", "Renode.exe")
            end
            if os.isfile(bin) then
                return {
                    name = package:name(),
                    version = package:version_str(),
                    installdir = package:installdir()
                }
            end
        end
        return nil
    end)

    on_install("linux", "macosx", "windows", function (package)
        import("core.base.option")

        cprint("${green}[renode]${clear} Installing %s...", package:version_str())

        if package:is_plat("macosx") then
            local originfile = package:originfile()
            if os.isfile(originfile) then
                local filesize = os.filesize(originfile)
                cprint("${green}[renode]${clear} DMG size: ${bright}%.2f MB${clear}", filesize / 1024 / 1024)
            end

            cprint("${green}[renode]${clear} Mounting DMG image...")
            local mountdir
            local result = os.iorunv("hdiutil", {"attach", originfile})
            if result then
                for _, line in ipairs(result:split("\n", {plain = true})) do
                    local pos = line:find("/Volumes", 1, true)
                    if pos then
                        mountdir = line:sub(pos):trim()
                        break
                    end
                end
            end

            local function safe_detach()
                if mountdir and os.isdir(mountdir) then
                    cprint("${green}[renode]${clear} Unmounting DMG...")
                    try { function() os.execv("hdiutil", {"detach", mountdir, "-force"}) end }
                end
            end

            if not mountdir or not os.isdir(mountdir) then
                raise("cannot mount DMG: %s", originfile)
            end
            cprint("${green}[renode]${clear} Mounted at: %s", mountdir)

            local app_dir = path.join(mountdir, "Renode.app/Contents/MacOS")
            if not os.isdir(app_dir) then
                safe_detach()
                raise("App not found in DMG at: %s", mountdir)
            end

            cprint("${green}[renode]${clear} Copying files...")
            local copy_ok = try { function()
                os.cp(path.join(app_dir, "*"), package:installdir())
                return true
            end }

            safe_detach()

            if not copy_ok then
                raise("Failed to copy files from DMG")
            end

            os.mkdir(package:installdir("bin"))
            local exe = path.join(package:installdir(), "Renode")
            local wrapper_path = path.join(package:installdir(), "bin", "renode")
            io.writefile(wrapper_path, string.format([=[#!/bin/sh
exec "%s" "$@"
]=], exe))
            os.runv("chmod", {"+x", wrapper_path})

        elseif package:is_plat("windows") then
            cprint("${green}[renode]${clear} Extracting archive...")
            os.cp(path.join(package:sourcedir(), "*"), package:installdir())

            os.mkdir(package:installdir("bin"))
            local exe = path.join(package:installdir(), "bin", "Renode.exe")
            if not os.isfile(exe) then
                local found = os.files(path.join(package:installdir(), "**", "Renode.exe"))
                if found and #found > 0 then
                    cprint("${green}[renode]${clear} Found at: %s", found[1])
                end
            end

        else
            local originfile = package:originfile()
            if os.isfile(originfile) then
                local filesize = os.filesize(originfile)
                cprint("${green}[renode]${clear} Archive size: ${bright}%.2f MB${clear}", filesize / 1024 / 1024)
            end

            cprint("${green}[renode]${clear} Extracting archive...")
            os.vrunv("tar", {"-xzf", originfile, "-C", package:installdir(), "--strip-components=1"})

            local script = path.join(package:installdir(), "renode")
            local bin = path.join(package:installdir(), "bin", "renode")
            if os.isfile(script) and not os.isfile(bin) then
                os.mkdir(package:installdir("bin"))
                io.writefile(bin, string.format([=[#!/bin/sh
exec "%s" "$@"
]=], script))
                os.runv("chmod", {"+x", bin})
            end
        end

        cprint("${green}[renode]${clear} Verifying installation...")
        local bin = path.join(package:installdir(), "bin", "renode")
        if is_host("windows") then
            bin = path.join(package:installdir(), "bin", "Renode.exe")
        end
        if not os.isfile(bin) then
            raise("Binary not found after installation: %s", bin)
        end

        package:addenv("PATH", "bin")
        cprint("${green}[renode]${clear} Installation completed successfully!")
    end)

    on_load(function (package)
        package:addenv("PATH", "bin")
    end)

    on_test(function (package)
        os.vrun("renode", {"--version"})
    end)

