package("riscv32-esp")

    set_kind("toolchain")
    set_homepage("https://github.com/espressif/crosstool-NG")
    set_description("Espressif GCC toolchain for 32-bit RISC-V Espressif SoCs (ESP32-C2/C3/C5/C6/C61/H2/H21/P4)")

    -- Versions map to upstream release tags `esp-<mapped>` from
    -- https://github.com/espressif/crosstool-NG/releases (e.g. version
    -- "14.2.0" maps to release tag "esp-14.2.0_20251107", archive prefix
    -- "riscv32-esp-elf-14.2.0_20251107"). The pinned snapshot is the
    -- toolchain recommended by ESP-IDF v5.5.3 (tools/tools.json, tool
    -- "riscv32-esp-elf"); it ships both the
    -- rv32imafc_zicsr_zifencei/ilp32f and
    -- rv32imafc_zicsr_zifencei_xesppie/ilp32f multilibs used by ESP32-P4.
    --
    -- Host coverage (all upstream-provided hosts):
    --   linux   x86_64 / aarch64(arm64) / armhf(armv*) / i386(i586)
    --   macosx  x86_64 / arm64(aarch64)
    --   windows x86_64(x64) / x86(i686)
    -- linux armel (arm-linux-gnueabi) is also published upstream but
    -- os.arch() cannot distinguish soft-float armel from armhf, so armv*
    -- hosts resolve to the gnueabihf build.
    local version_map = {
        ["14.2.0"] = "14.2.0_20251107",
    }

    local function esp_version(version)
        return version_map[tostring(version)]
    end

    if is_host("linux") then
        if os.arch():find("arm64") or os.arch():find("aarch64") then
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-aarch64-linux-gnu.tar.xz", {version = esp_version})
            add_versions("14.2.0", "072a553453691fbd98fe82b6efa9a2fa6beb7d2c90aed4463353bc33378e83bf")
        elseif os.arch():find("arm") then
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-arm-linux-gnueabihf.tar.xz", {version = esp_version})
            add_versions("14.2.0", "6e4bee2ec2c8e922a890b59731746853ea8f14e118fcd6ae5fa58fea5c1aa2eb")
        elseif os.arch():find("i[0-9]86") or os.arch() == "x86" then
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-i586-linux-gnu.tar.xz", {version = esp_version})
            add_versions("14.2.0", "402ed7d177e744916df8afc74c5e5a9cfd40557df07a6a7fc52b00917b15f97b")
        else
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-x86_64-linux-gnu.tar.xz", {version = esp_version})
            add_versions("14.2.0", "1d3a1b6a064686d9b77c4db7731f82e26c072e312e27969c45fe96410ecb2671")
        end
    elseif is_host("windows") then
        if os.arch() == "x86" then
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-i686-w64-mingw32.zip", {version = esp_version})
            add_versions("14.2.0", "7670128df99adbdcbc99ebbdccda19347daf2fd191aab1eb22c24ae1c4d77226")
        else
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-x86_64-w64-mingw32.zip", {version = esp_version})
            add_versions("14.2.0", "373abecd1cdfd480b09b8659e319e636064f99fec46f635a05c5413e5f009c05")
        end
    elseif is_host("macosx") then
        if os.arch() ~= "arm64" then
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-x86_64-apple-darwin.tar.xz", {version = esp_version})
            add_versions("14.2.0", "d413836fa000f095d041a35950a45f82e2ff669995c8d6a09fa4d05e5c4ed258")
        else
            add_urls("https://github.com/espressif/crosstool-NG/releases/download/esp-$(version)/riscv32-esp-elf-$(version)-aarch64-apple-darwin.tar.xz", {version = esp_version})
            add_versions("14.2.0", "cedfcdaf8f165bd3e11ca4ee46b71d5b561fab93407eb8203812f9c14b1c7714")
        end
    end

    on_load(function (package)
        local installdir = package:installdir()
        local gcc = path.join(installdir, "bin", "riscv32-esp-elf-gcc")
        if is_host("windows") then
            gcc = gcc .. ".exe"
        end
        if not os.isdir(installdir) or not os.isfile(gcc) then
            cprint("${green}[riscv32-esp]${clear} Preparing to install %s", package:version_str())
            cprint("${green}[riscv32-esp]${clear} Expected download size: ~300MB")
            cprint("${green}[riscv32-esp]${clear} Expected install size: ~1.5GB")
            cprint("${green}[riscv32-esp]${clear} Download may take several minutes depending on your connection...")
        end

        package:addenv("PATH", "bin")

        import("core.base.global")
        local toolchain_file = path.join(package:scriptdir(), "toolchains/xmake.lua")
        if os.isfile(toolchain_file) then
            local user_toolchain_dir = path.join(global.directory(), "toolchains", "riscv32-esp")
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

    on_install("linux", "windows", "macosx", function (package)
        import("core.base.option")

        cprint("${green}[riscv32-esp]${clear} Installing %s...", package:version_str())
        local originfile = package:originfile()
        if not originfile or not os.isfile(originfile) then
            raise("riscv32-esp: archive not found: %s", tostring(originfile))
        end
        local filesize = os.filesize(originfile)
        cprint("${green}[riscv32-esp]${clear} Archive size: ${bright}%.2f MB${clear}", filesize / 1024 / 1024)

        cprint("${green}[riscv32-esp]${clear} Extracting toolchain files...")
        if originfile:endswith(".zip") then
            import("utils.archive")
            local tmpdir = path.join(os.tmpdir(), "riscv32-esp-extract")
            os.rm(tmpdir)
            archive.extract(originfile, tmpdir)
            local topdirs = os.dirs(path.join(tmpdir, "*"))
            if #topdirs == 1 then
                os.mv(path.join(topdirs[1], "*"), package:installdir())
            else
                os.mv(path.join(tmpdir, "*"), package:installdir())
            end
            os.rm(tmpdir)
        else
            if option.get("verbose") or option.get("diagnosis") then
                os.vrunv("tar", {"-xvf", originfile, "-C", package:installdir(), "--strip-components=1"})
            else
                os.vrunv("tar", {"-xf", originfile, "-C", package:installdir(), "--strip-components=1"})
            end
        end

        cprint("${green}[riscv32-esp]${clear} Setting up toolchain binaries...")
        if not is_host("windows") then
            local bindir = path.join(package:installdir(), "bin")
            if os.isdir(bindir) then
                os.vrunv("chmod", {"-R", "+x", bindir})
            end
        end

        cprint("${green}[riscv32-esp]${clear} Verifying installation...")
        local bindir = path.join(package:installdir(), "bin")
        local exe = is_host("windows") and "riscv32-esp-elf-gcc.exe" or "riscv32-esp-elf-gcc"
        local exe_path = path.join(bindir, exe)
        if not os.isfile(exe_path) then
            raise("riscv32-esp-elf-gcc not found after installation: %s", exe_path)
        end

        cprint("${green}[riscv32-esp]${clear} Installation completed successfully!")
        cprint("${green}[riscv32-esp]${clear} Toolchain installed to: ${bright}%s${clear}", package:installdir())
    end)

    on_test(function (package)
        local exe = path.join(package:installdir(), "bin", "riscv32-esp-elf-gcc")
        if is_host("windows") then
            exe = exe .. ".exe"
        end
        os.vrunv(exe, {"--version"})
        os.vrunv(exe, {"-print-multi-lib"})
    end)
