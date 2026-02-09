-- plugins/phc/modules/install_binary_app.lua
--
-- binary-app インストールテンプレート。
-- renode 等のバイナリアプリケーション用。
-- macOS DMG (.app) / Linux tar / Windows zip + wrapper script 生成。

---------------------------------------------------------------
-- generate: on_fetch / on_load / on_install / on_test のコード行を返す
---------------------------------------------------------------
function generate(pkg_name, config)
    local lines = {}
    local meta = config.metadata or {}
    local ic = config.install_config or {}
    local label = pkg_name
    local wrapper = ic.wrapper or {}
    local wrapper_name = wrapper.name or pkg_name
    local windows_name = wrapper.windows_name or (pkg_name .. ".exe")

    -- ── on_fetch ──
    table.insert(lines, format('    on_fetch(function (package, opt)'))
    table.insert(lines, format('        if os.isdir(package:installdir()) then'))
    table.insert(lines, format('            local bin = path.join(package:installdir(), "bin", "%s")', wrapper_name))
    table.insert(lines, format('            if is_host("windows") then'))
    table.insert(lines, format('                bin = path.join(package:installdir(), "bin", "%s")', windows_name))
    table.insert(lines, format('            end'))
    table.insert(lines, format('            if os.isfile(bin) then'))
    table.insert(lines, format('                return {'))
    table.insert(lines, format('                    name = package:name(),'))
    table.insert(lines, format('                    version = package:version_str(),'))
    table.insert(lines, format('                    installdir = package:installdir()'))
    table.insert(lines, format('                }'))
    table.insert(lines, format('            end'))
    table.insert(lines, format('        end'))
    table.insert(lines, format('        return nil'))
    table.insert(lines, format('    end)'))

    -- ── on_install ──
    table.insert(lines, '')
    table.insert(lines, format('    on_install("linux", "macosx", "windows", function (package)'))
    table.insert(lines, format('        import("core.base.option")'))
    table.insert(lines, '')
    table.insert(lines, format('        cprint("${green}[%s]${clear} Installing %%s...", package:version_str())', label))

    -- macOS DMG handling
    if ic.macos_app then
        table.insert(lines, '')
        table.insert(lines, format('        if package:is_plat("macosx") then'))
        table.insert(lines, format('            local originfile = package:originfile()'))
        table.insert(lines, format('            if os.isfile(originfile) then'))
        table.insert(lines, format('                local filesize = os.filesize(originfile)'))
        table.insert(lines, format('                cprint("${green}[%s]${clear} DMG size: ${bright}%%.2f MB${clear}", filesize / 1024 / 1024)', label))
        table.insert(lines, format('            end'))
        table.insert(lines, '')
        table.insert(lines, format('            cprint("${green}[%s]${clear} Mounting DMG image...")', label))
        table.insert(lines, format('            local mountdir'))
        table.insert(lines, format('            local result = os.iorunv("hdiutil", {"attach", originfile})'))
        table.insert(lines, format('            if result then'))
        table.insert(lines, format('                for _, line in ipairs(result:split("\\n", {plain = true})) do'))
        table.insert(lines, format('                    local pos = line:find("/Volumes", 1, true)'))
        table.insert(lines, format('                    if pos then'))
        table.insert(lines, format('                        mountdir = line:sub(pos):trim()'))
        table.insert(lines, format('                        break'))
        table.insert(lines, format('                    end'))
        table.insert(lines, format('                end'))
        table.insert(lines, format('            end'))
        table.insert(lines, '')
        table.insert(lines, format('            local function safe_detach()'))
        table.insert(lines, format('                if mountdir and os.isdir(mountdir) then'))
        table.insert(lines, format('                    cprint("${green}[%s]${clear} Unmounting DMG...")', label))
        table.insert(lines, format('                    try { function() os.execv("hdiutil", {"detach", mountdir, "-force"}) end }'))
        table.insert(lines, format('                end'))
        table.insert(lines, format('            end'))
        table.insert(lines, '')
        table.insert(lines, format('            if not mountdir or not os.isdir(mountdir) then'))
        table.insert(lines, format('                raise("cannot mount DMG: %%s", originfile)'))
        table.insert(lines, format('            end'))
        table.insert(lines, format('            cprint("${green}[%s]${clear} Mounted at: %%s", mountdir)', label))
        table.insert(lines, '')
        table.insert(lines, format('            local app_dir = path.join(mountdir, "%s")', ic.macos_app))
        table.insert(lines, format('            if not os.isdir(app_dir) then'))
        table.insert(lines, format('                safe_detach()'))
        table.insert(lines, format('                raise("App not found in DMG at: %%s", mountdir)'))
        table.insert(lines, format('            end'))
        table.insert(lines, '')
        table.insert(lines, format('            cprint("${green}[%s]${clear} Copying files...")', label))
        table.insert(lines, format('            local copy_ok = try { function()'))
        table.insert(lines, format('                os.cp(path.join(app_dir, "*"), package:installdir())'))
        table.insert(lines, format('                return true'))
        table.insert(lines, format('            end }'))
        table.insert(lines, '')
        table.insert(lines, format('            safe_detach()'))
        table.insert(lines, '')
        table.insert(lines, format('            if not copy_ok then'))
        table.insert(lines, format('                raise("Failed to copy files from DMG")'))
        table.insert(lines, format('            end'))
        table.insert(lines, '')

        -- Create wrapper script for macOS
        -- The main executable name: capitalize first letter of wrapper_name
        local exe_name = wrapper_name:sub(1,1):upper() .. wrapper_name:sub(2)
        table.insert(lines, format('            os.mkdir(package:installdir("bin"))'))
        table.insert(lines, format('            local exe = path.join(package:installdir(), "%s")', exe_name))
        table.insert(lines, format('            local wrapper_path = path.join(package:installdir(), "bin", "%s")', wrapper_name))
        table.insert(lines, format([[            io.writefile(wrapper_path, string.format([=[#!/bin/sh
exec "%%s" "$@"
]=], exe))]]))
        table.insert(lines, format('            os.runv("chmod", {"+x", wrapper_path})'))
        table.insert(lines, '')
        table.insert(lines, format('        elseif package:is_plat("windows") then'))
    else
        table.insert(lines, '')
        table.insert(lines, format('        if package:is_plat("windows") then'))
    end

    -- Windows
    table.insert(lines, format('            cprint("${green}[%s]${clear} Extracting archive...")', label))
    table.insert(lines, format('            os.cp(path.join(package:sourcedir(), "*"), package:installdir())'))
    table.insert(lines, '')
    table.insert(lines, format('            os.mkdir(package:installdir("bin"))'))
    table.insert(lines, format('            local exe = path.join(package:installdir(), "bin", "%s")', windows_name))
    table.insert(lines, format('            if not os.isfile(exe) then'))
    table.insert(lines, format('                local found = os.files(path.join(package:installdir(), "**", "%s"))', windows_name))
    table.insert(lines, format('                if found and #found > 0 then'))
    table.insert(lines, format('                    cprint("${green}[%s]${clear} Found at: %%s", found[1])', label))
    table.insert(lines, format('                end'))
    table.insert(lines, format('            end'))
    table.insert(lines, '')
    table.insert(lines, format('        else'))

    -- Linux
    table.insert(lines, format('            local originfile = package:originfile()'))
    table.insert(lines, format('            if os.isfile(originfile) then'))
    table.insert(lines, format('                local filesize = os.filesize(originfile)'))
    table.insert(lines, format('                cprint("${green}[%s]${clear} Archive size: ${bright}%%.2f MB${clear}", filesize / 1024 / 1024)', label))
    table.insert(lines, format('            end'))
    table.insert(lines, '')
    table.insert(lines, format('            cprint("${green}[%s]${clear} Extracting archive...")', label))
    table.insert(lines, format('            os.vrunv("tar", {"-xzf", originfile, "-C", package:installdir(), "--strip-components=1"})'))
    table.insert(lines, '')

    -- Create wrapper if needed
    table.insert(lines, format('            local script = path.join(package:installdir(), "%s")', wrapper_name))
    table.insert(lines, format('            local bin = path.join(package:installdir(), "bin", "%s")', wrapper_name))
    table.insert(lines, format('            if os.isfile(script) and not os.isfile(bin) then'))
    table.insert(lines, format('                os.mkdir(package:installdir("bin"))'))
    table.insert(lines, format([[                io.writefile(bin, string.format([=[#!/bin/sh
exec "%%s" "$@"
]=], script))]]))
    table.insert(lines, format('                os.runv("chmod", {"+x", bin})'))
    table.insert(lines, format('            end'))
    table.insert(lines, format('        end'))

    -- Verify
    table.insert(lines, '')
    table.insert(lines, format('        cprint("${green}[%s]${clear} Verifying installation...")', label))
    table.insert(lines, format('        local bin = path.join(package:installdir(), "bin", "%s")', wrapper_name))
    table.insert(lines, format('        if is_host("windows") then'))
    table.insert(lines, format('            bin = path.join(package:installdir(), "bin", "%s")', windows_name))
    table.insert(lines, format('        end'))
    table.insert(lines, format('        if not os.isfile(bin) then'))
    table.insert(lines, format('            raise("Binary not found after installation: %%s", bin)'))
    table.insert(lines, format('        end'))
    table.insert(lines, '')
    table.insert(lines, format('        package:addenv("PATH", "bin")'))
    table.insert(lines, format('        cprint("${green}[%s]${clear} Installation completed successfully!")', label))
    table.insert(lines, format('    end)'))

    -- ── on_load ──
    table.insert(lines, '')
    table.insert(lines, format('    on_load(function (package)'))
    table.insert(lines, format('        package:addenv("PATH", "bin")'))
    table.insert(lines, format('    end)'))

    -- ── on_test ──
    if ic.bin_verify and #ic.bin_verify > 0 then
        table.insert(lines, '')
        table.insert(lines, format('    on_test(function (package)'))
        for _, cmd in ipairs(ic.bin_verify) do
            local parts = cmd:split("%s+")
            local bin = parts[1]
            local args = {}
            for i = 2, #parts do
                table.insert(args, parts[i])
            end
            if #args > 0 then
                local args_str = table.concat(args, '", "')
                table.insert(lines, format('        os.vrun("%s", {"%s"})', bin, args_str))
            else
                table.insert(lines, format('        os.vrun("%s", {"--version"})', bin))
            end
        end
        table.insert(lines, format('    end)'))
    end

    return lines
end
