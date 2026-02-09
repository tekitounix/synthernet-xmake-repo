package("gcc-arm")

    set_kind("toolchain")
    set_homepage("https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gcc-arm")
    set_description("GNU Arm Embedded Toolchain")

    local version_map = {
        ["14.2.1"] = "14.2.rel1",
        ["14.3.1"] = "14.3.rel1",
    }

    if is_host("linux") then
        if os.arch():find("arm64") then
            add_urls("https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/$(version)/binrel/arm-gnu-toolchain-$(version)-aarch64-arm-none-eabi.tar.xz", {version = function (version)
                return version_map[tostring(version)]
            end})
            add_versions("14.3.1", "2d465847eb1d05f876270494f51034de9ace9abe87a4222d079f3360240184d3")
            add_versions("14.2.1", "87330bab085dd8749d4ed0ad633674b9dc48b237b61069e3b481abd364d0a684")
        else
            add_urls("https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/$(version)/binrel/arm-gnu-toolchain-$(version)-x86_64-arm-none-eabi.tar.xz", {version = function (version)
                return version_map[tostring(version)]
            end})
            add_versions("14.3.1", "8f6903f8ceb084d9227b9ef991490413014d991874a1e34074443c2a72b14dbd")
            add_versions("14.2.1", "62a63b981fe391a9cbad7ef51b17e49aeaa3e7b0d029b36ca1e9c3b2a9b78823")
        end
    elseif is_host("windows") then
        if os.arch() == "x86" then
            add_urls("https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/$(version)/binrel/arm-gnu-toolchain-$(version)-mingw-w64-i686-arm-none-eabi.zip", {version = function (version)
                return version_map[tostring(version)]
            end})
            add_versions("14.3.1", "836ebe51fd71b6542dd7884c8fb2011192464b16c28e4b38fddc9350daba5ee8")
            add_versions("14.2.1", "6facb152ce431ba9a4517e939ea46f057380f8f1e56b62e8712b3f3b87d994e1")
        else
            add_urls("https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/$(version)/binrel/arm-gnu-toolchain-$(version)-mingw-w64-x86_64-arm-none-eabi.zip", {version = function (version)
                return version_map[tostring(version)]
            end})
            add_versions("14.3.1", "864c0c8815857d68a1bbba2e5e2782255bb922845c71c97636004a3d74f60986")
            add_versions("14.2.1", "f074615953f76036e9a51b87f6577fdb4ed8e77d3322a6f68214e92e7859888f")
        end
    elseif is_host("macosx") then
        if os.arch() ~= "arm64" then
            add_urls("https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/$(version)/binrel/arm-gnu-toolchain-$(version)-darwin-x86_64-arm-none-eabi.tar.xz", {version = function (version)
                return version_map[tostring(version)]
            end})
            add_versions("14.2.1", "2d9e717dd4f7751d18936ae1365d25916534105ebcb7583039eff1092b824505")
        else
            add_urls("https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/$(version)/binrel/arm-gnu-toolchain-$(version)-darwin-arm64-arm-none-eabi.tar.xz", {version = function (version)
                return version_map[tostring(version)]
            end})
            add_versions("14.3.1", "30f4d08b219190a37cded6aa796f4549504902c53cfc3c7e044a8490b6eba1f7")
            add_versions("14.2.1", "c7c78ffab9bebfce91d99d3c24da6bf4b81c01e16cf551eb2ff9f25b9e0a3818")
        end
    end

    on_load(function (package)
        if package:is_plat("macosx") and package:arch() == "x86_64" then
            if package:version():eq("14.3.1") then
                raise("gcc-arm 14.3.1 is not available for macOS x64")
            end
        end

        local installdir = package:installdir()
        if not os.isdir(installdir) or not os.isfile(path.join(installdir, "bin", "arm-none-eabi-gcc")) then
            cprint("${green}[gcc-arm]${clear} Preparing to install %s", package:version_str())
            cprint("${green}[gcc-arm]${clear} Expected download size: ~130MB")
            cprint("${green}[gcc-arm]${clear} Expected install size: ~1GB")
            cprint("${green}[gcc-arm]${clear} Download may take several minutes depending on your connection...")
        end

        package:addenv("PATH", "bin")

        import("core.base.global")
        local toolchain_file = path.join(package:scriptdir(), "toolchains/xmake.lua")
        if os.isfile(toolchain_file) then
            local user_toolchain_dir = path.join(global.directory(), "toolchains", "gcc-arm")
            local dest_file = path.join(user_toolchain_dir, "xmake.lua")
            local need_update = true
            if os.isfile(dest_file) then
                local src_content = io.readfile(toolchain_file)
                local dst_content = io.readfile(dest_file)
                if src_content == dst_content then
                    need_update = false
                end
            end
            if need_update then
                os.mkdir(user_toolchain_dir)
                os.cp(toolchain_file, dest_file)
                print("=> Toolchain definition installed to: %s", user_toolchain_dir)
            end
        end
    end)

    on_download(function (package, opt)
        cprint("${green}[gcc-arm]${clear} Downloading %s...", package:version_str())
        cprint("${green}[gcc-arm]${clear} File: %s", path.filename(opt.url))
        cprint("${green}[gcc-arm]${clear} This is a large download (~130MB)")

        import("net.http")
        import("utils.progress")

        local downloadfile = opt.outputfile
        local filesize = nil
        local ok, errors = try { function()
            filesize = http.downloadsize(opt.url)
            return true
        end }

        if filesize and filesize > 0 then
            cprint("${green}[gcc-arm]${clear} Download size: ${bright}%.2f MB${clear}", filesize / 1024 / 1024)
            progress.show(opt.progress or 0, "${green}downloading${clear} %s", path.filename(opt.url))
            http.download(opt.url, downloadfile, {
                headers = opt.headers,
                progress = function (progress_info)
                    progress.show(progress_info, "${green}downloading${clear} %s", path.filename(opt.url))
                end
            })
        else
            cprint("${green}[gcc-arm]${clear} Downloading... (progress not available)")
            http.download(opt.url, downloadfile, {headers = opt.headers})
        end

        cprint("${green}[gcc-arm]${clear} Download completed!")

        local sourcedir = path.join(package:cachedir(), "source")
        os.mkdir(sourcedir)
        io.writefile(path.join(sourcedir, ".placeholder"), "")

        return downloadfile
    end)

    on_install("@windows", "@linux", "@macosx", function(package)
        import("core.base.option")

        cprint("${green}[gcc-arm]${clear} Installing %s...", package:version_str())
        local cachedir = package:cachedir()
        local originfile = nil
        for _, file in ipairs(os.files(path.join(cachedir, "*.tar.xz"))) do
            originfile = file
            break
        end
        if not originfile then
            for _, file in ipairs(os.files(path.join(cachedir, "*.zip"))) do
                originfile = file
                break
            end
        end
        if not originfile or not os.isfile(originfile) then
            raise("gcc-arm: Archive not found in cache: %s", cachedir)
        end
        if os.isfile(originfile) then
            local filesize = os.filesize(originfile)
            cprint("${green}[gcc-arm]${clear} Archive size: ${bright}%.2f MB${clear}", filesize / 1024 / 1024)
        end

        cprint("${green}[gcc-arm]${clear} Extracting toolchain files...")
        if option.get("verbose") or option.get("diagnosis") then
            os.vrunv("tar", {"-xJvf", originfile, "-C", package:installdir(), "--strip-components=1"})
        else
            cprint("${green}[gcc-arm]${clear} Extracting (this may take several minutes)...")
            local has_pv = try { function() return os.iorun("which pv") end }
            if has_pv and has_pv:trim() ~= "" then
                os.vexecv("bash", {"-c", format("pv %s | tar -xJf - -C %s --strip-components=1", originfile, package:installdir())})
            else
                io.write("[gcc-arm] Progress: ")
                io.flush()
                local tmpscript = os.tmpfile() .. ".sh"
                io.writefile(tmpscript, format([=[
#!/bin/bash
tar -xJf "%s" -C "%s" --strip-components=1 &
TAR_PID=$!
while kill -0 $TAR_PID 2>/dev/null; do
    printf "."
    sleep 2
done
printf " done!\n"
]=], originfile, package:installdir()))
                os.vexecv("bash", {tmpscript})
                os.rm(tmpscript)
            end
        end

        cprint("${green}[gcc-arm]${clear} Setting up toolchain binaries...")
        if not is_host("windows") then
            local bindir = path.join(package:installdir(), "bin")
            if os.isdir(bindir) then
                os.vrunv("chmod", {"-R", "+x", bindir})
            end
        end

        cprint("${green}[gcc-arm]${clear} Verifying installation...")
        local bindir = path.join(package:installdir(), "bin")
        local exe = is_host("windows") and "arm-none-eabi-gcc.exe" or "arm-none-eabi-gcc"
        local exe_path = path.join(bindir, exe)
        if not os.isfile(exe_path) then
            raise("arm-none-eabi-gcc not found after installation: %s", exe_path)
        end

        cprint("${green}[gcc-arm]${clear} Installation completed successfully!")
        cprint("${green}[gcc-arm]${clear} Toolchain installed to: ${bright}%s${clear}", package:installdir())
    end)

    on_test(function (package)
        local exe = path.join(package:installdir(), "bin", "arm-none-eabi-gcc")
        if is_host("windows") then
            exe = exe .. ".exe"
        end
        os.vrunv(exe, {"--version"})
        os.vrunv(exe, {"--target-help"})
    end)

