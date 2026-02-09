package("clang-arm")

    set_kind("toolchain")
    set_homepage("https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm")
    set_description("A project dedicated to building LLVM toolchain for 32-bit Arm embedded targets.")

    if is_host("linux") then
        if os.arch():find("arm64") then
            add_urls("https://github.com/arm/arm-toolchain/releases/download/release-$(version)-ATfE/ATfE-$(version)-Linux-AArch64.tar.xz")
            add_versions("21.1.1", "dfd93d7c79f26667f4baf7f388966aa4cbfd938bc5cbcf0ae064553faf3e9604")
            add_versions("21.1.0", "04969ac437ff659f2b35e73bf4be857b2ec5bb22a2025cfba28c51aab6d51d69")
            add_versions("20.1.0", "2fa9220f64097b71c07e6de2917f33fda1bb736964730786e90a430fdc0fa6be")
            -- legacy source
            add_urls("https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/release-$(version)/LLVM-ET-Arm-$(version)-Linux-AArch64.tar.xz",
                     "https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/preview-$(version)/LLVM-ET-Arm-$(version)-Linux-AArch64.tar.xz")
            add_versions("19.1.5", "5e2f6b8c77464371ae2d7445114b4bdc19f56138e8aa864495181b52f57d0b85")
            add_versions("19.1.1", "0172cf1768072a398572cb1fc0bb42551d60181b3280f12c19401d94ca5162e6")
            add_versions("18.1.3", "47cd08804e22cdd260be43a00b632f075c3e1ad5a2636537c5589713ab038505")
        else
            add_urls("https://github.com/arm/arm-toolchain/releases/download/release-$(version)-ATfE/ATfE-$(version)-Linux-x86_64.tar.xz")
            add_versions("21.1.1", "fd7fcc2eb4c88c53b71c45f9c6aa83317d45da5c1b51b0720c66f1ac70151e6e")
            add_versions("21.1.0", "40b59c426e4057fbfde3260939fa67f240312661bd96c96be752033a69d41c6e")
            add_versions("20.1.0", "c1179396608c07bf68f3014923cfdfcd11c8402a3732f310c23d07c9a726b275")
            -- legacy source
            add_urls("https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/release-$(version)/LLVM-ET-Arm-$(version)-Linux-x86_64.tar.xz",
                     "https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/preview-$(version)/LLVM-ET-Arm-$(version)-Linux-x86_64.tar.xz")
            add_versions("19.1.5", "34ee877aadc78c5e9f067e603a1bc9745ed93ca7ae5dbfc9b4406508dc153920")
            add_versions("19.1.1", "f659c625302f6d3fb50f040f748206f6fd6bb1fc7e398057dd2deaf1c1f5e8d1")
            add_versions("18.1.3", "7afae248ac33f7daee95005d1b0320774d8a5495e7acfb9bdc9475d3ad400ac9")
        end
    elseif is_host("windows") then
        add_urls("https://github.com/arm/arm-toolchain/releases/download/release-$(version)-ATfE/ATfE-$(version)-Windows-x86_64.zip")
        add_versions("21.1.1", "12e21352acd6ce514df77b6c9ff77e20978cbb44d4c7f922bd44c60594869460")
        add_versions("21.1.0", "dc9aa044e68614fbf3251cddd42447819480d9a2f3de50cd9be7d76ad8f3523e")
        add_versions("20.1.0", "0214ad4283c3b487bc96705121d06c74d6643ce3c2b3a1bad5e7c42789fe3c8f")
        -- legacy source
        add_urls("https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/release-$(version)/LLVM-ET-Arm-$(version)-Windows-x86_64.zip",
                 "https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/preview-$(version)/LLVM-ET-Arm-$(version)-Windows-x86_64.zip")
        add_versions("19.1.5", "f4b26357071a5bae0c1dfe5e0d5061595a8cc1f5d921b6595cc3b269021384eb")
        add_versions("19.1.1", "3bf972ecff428cf9398753f7f2bef11220a0bfa4119aabdb1b6c8c9608105ee4")
        add_versions("18.1.3", "3013dcf1dba425b644e64cb4311b9b7f6ff26df01ba1fcd943105d6bb2a6e68b")
    elseif is_host("macosx") then
        add_urls("https://github.com/arm/arm-toolchain/releases/download/release-$(version)-ATfE/ATfE-$(version)-Darwin-universal.dmg")
        add_versions("21.1.1", "2173cdb297ead08965ae1a34e4e92389b9024849b4ff4eb875652ff9667b7b2a")
        add_versions("21.1.0", "a310b4e8603bc25d71444d8a70e8ee9c2362cb4c8f4dcdb91a35fa371b45f425")
        add_versions("20.1.0", "11505eed22ceafcb52ef3d678a0640c67af92f511a9dd14309a44a766fafd703")
        -- legacy source
        add_urls("https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/release-$(version)/LLVM-ET-Arm-$(version)-Darwin-universal.dmg",
                 "https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/preview-$(version)/LLVM-ET-Arm-$(version)-Darwin-universal.dmg")
        add_versions("19.1.5", "0451e67dc9a9066c17f746c26654962fa3889d4df468db1245d1bae69438eaf5")
        add_versions("19.1.1", "32c9253ab05e111cffc1746864a3e1debffb7fbb48631da88579e4f830fca163")
        add_versions("18.1.3", "2864324ddff4d328e4818cfcd7e8c3d3970e987edf24071489f4182b80187a48")
    end

    on_load(function (package)
        local installdir = package:installdir()
        if not os.isdir(installdir) or not os.isfile(path.join(installdir, "bin", "clang")) then
            cprint("${green}[clang-arm]${clear} Preparing to install %s", package:version_str())
            cprint("${green}[clang-arm]${clear} Expected download size: ~200MB")
            cprint("${green}[clang-arm]${clear} Expected install size: ~800MB")
            cprint("${green}[clang-arm]${clear} Download may take several minutes depending on your connection...")
        end

        package:addenv("PATH", "bin")

        import("core.base.global")
        local toolchain_file = path.join(package:scriptdir(), "toolchains/xmake.lua")
        if os.isfile(toolchain_file) then
            local user_toolchain_dir = path.join(global.directory(), "toolchains", "clang-arm")
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

    on_install("linux", "windows", "macosx", function(package)
        import("core.base.option")

        cprint("${green}[clang-arm]${clear} Installing %s...", package:version_str())

        if package:is_plat("macosx") then
            local originfile = package:originfile()
            if os.isfile(originfile) then
                local filesize = os.filesize(originfile)
                cprint("${green}[clang-arm]${clear} DMG size: ${bright}%.2f MB${clear}", filesize / 1024 / 1024)
            end

            cprint("${green}[clang-arm]${clear} Mounting DMG image...")
            local mountdir
            local result = os.iorunv("hdiutil", {"attach", package:originfile()})
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
                    cprint("${green}[clang-arm]${clear} Unmounting DMG...")
                    try { function() os.execv("hdiutil", {"detach", mountdir, "-force"}) end }
                end
            end

            if not mountdir or not os.isdir(mountdir) then
                raise("cannot mount DMG: %s", package:originfile())
            end
            cprint("${green}[clang-arm]${clear} Mounted at: %s", mountdir)

            cprint("${green}[clang-arm]${clear} Looking for toolchain directory...")
            local toolchaindir
            for _, dir in ipairs(os.dirs(path.join(mountdir, "*"))) do
                local basename = path.basename(dir)
                if basename:find("ATfE") or basename:find("LLVM%-ET%-Arm") then
                    toolchaindir = dir
                    break
                end
            end
            if not toolchaindir then
                safe_detach()
                raise("toolchain directory not found in DMG: %s", mountdir)
            end
            cprint("${green}[clang-arm]${clear} Found: %s", path.basename(toolchaindir))

            cprint("${green}[clang-arm]${clear} Copying toolchain files...")
            local copy_ok = try { function()
                local rsync_path = try { function() return os.iorun("which rsync") end }
                if rsync_path and rsync_path:trim() ~= "" then
                    os.vrunv("rsync", {"-ah", "--progress", toolchaindir .. "/", package:installdir() .. "/"})
                else
                    os.vexecv("bash", {"-c", format("cp -R %s/* %s", toolchaindir, package:installdir())})
                end
                return true
            end }

            safe_detach()

            if not copy_ok then
                raise("Failed to copy files from DMG")
            end
        else
            local originfile = package:originfile()
            if os.isfile(originfile) then
                local filesize = os.filesize(originfile)
                cprint("${green}[clang-arm]${clear} Archive size: ${bright}%.2f MB${clear}", filesize / 1024 / 1024)
            end

            cprint("${green}[clang-arm]${clear} Extracting toolchain files...")
            if option.get("verbose") or option.get("diagnosis") then
                os.vrunv("tar", {"-xzvf", originfile, "-C", package:installdir(), "--strip-components=1"})
            else
                os.vrunv("tar", {"-xzf", originfile, "-C", package:installdir(), "--strip-components=1"})
            end
        end

        cprint("${green}[clang-arm]${clear} Setting up toolchain binaries...")
        if not is_host("windows") then
            local bindir = path.join(package:installdir(), "bin")
            if os.isdir(bindir) then
                os.vrunv("chmod", {"-R", "+x", bindir})
            end
        end

        cprint("${green}[clang-arm]${clear} Verifying installation...")
        local bindir = path.join(package:installdir(), "bin")
        local exe = is_host("windows") and "clang.exe" or "clang"
        local exe_path = path.join(bindir, exe)
        if not os.isfile(exe_path) then
            raise("clang not found after installation: %s", exe_path)
        end

        cprint("${green}[clang-arm]${clear} Installation completed successfully!")
        cprint("${green}[clang-arm]${clear} Toolchain installed to: ${bright}%s${clear}", package:installdir())
    end)

    on_test(function (package)
        local exe = path.join(package:installdir(), "bin", "clang")
        if is_host("windows") then
            exe = exe .. ".exe"
        end
        os.vrunv(exe, {"--version"})
        os.vrunv(exe, {"--target=arm-none-eabi", "--version"})
    end)

