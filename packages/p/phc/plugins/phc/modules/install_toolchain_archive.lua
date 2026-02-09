-- plugins/phc/modules/install_toolchain_archive.lua
--
-- toolchain-archive インストールテンプレート。
-- clang-arm, gcc-arm 等のツールチェインパッケージ用。
-- macOS DMG / Linux tar / Windows zip 展開 + toolchain定義インストール。

---------------------------------------------------------------
-- generate: on_load / on_install / on_test のコード行を返す
---------------------------------------------------------------
function generate(pkg_name, config)
    local lines = {}
    local meta = config.metadata or {}
    local ic = config.install_config or {}
    local label = pkg_name

    local function L(s) table.insert(lines, s) end

    -- DMG判定: macOSアセットが .dmg の場合のみ
    local has_dmg = false
    for pid, asset in pairs(config.assets) do
        if pid:find("^macos") and asset:find("%.dmg$") then has_dmg = true; break end
    end

    -- extraction のインデント: DMGありなら else 内（3レベル）、なしなら直下（2レベル）
    local ei = has_dmg and "            " or "        "  -- extraction indent

    -- ── on_load ──
    L('    on_load(function (package)')

    -- exclusions → version制約
    if config.exclusions then
        for ver, platforms in pairs(config.exclusions) do
            for _, pid in ipairs(platforms) do
                if pid == "macos-x86_64" then
                    L('        if package:is_plat("macosx") and package:arch() == "x86_64" then')
                    L(format('            if package:version():eq("%s") then', ver))
                    L(format('                raise("%s %s is not available for macOS x64")', pkg_name, ver))
                    L('            end')
                    L('        end')
                end
            end
        end
        L('')
    end

    local bin_check = ic.bin_check or "gcc"
    L('        local installdir = package:installdir()')
    L(format('        if not os.isdir(installdir) or not os.isfile(path.join(installdir, "bin", "%s")) then', bin_check))
    L(format('            cprint("${green}[%s]${clear} Preparing to install %%s", package:version_str())', label))
    if ic.download_size then
        L(format('            cprint("${green}[%s]${clear} Expected download size: %s")', label, ic.download_size))
    end
    if ic.install_size then
        L(format('            cprint("${green}[%s]${clear} Expected install size: %s")', label, ic.install_size))
    end
    L(format('            cprint("${green}[%s]${clear} Download may take several minutes depending on your connection...")', label))
    L('        end')
    L('')
    L('        package:addenv("PATH", "bin")')

    if ic.toolchain_def then
        L('')
        L('        import("core.base.global")')
        L(format('        local toolchain_file = path.join(package:scriptdir(), "%s")', ic.toolchain_def))
        L('        if os.isfile(toolchain_file) then')
        L(format('            local user_toolchain_dir = path.join(global.directory(), "toolchains", "%s")', pkg_name))
        L('            local dest_file = path.join(user_toolchain_dir, "xmake.lua")')
        L('            local need_update = true')
        L('            if os.isfile(dest_file) then')
        L('                local src_content = io.readfile(toolchain_file)')
        L('                local dst_content = io.readfile(dest_file)')
        L('                if src_content == dst_content then')
        L('                    need_update = false')
        L('                end')
        L('            end')
        L('            if need_update then')
        L('                os.mkdir(user_toolchain_dir)')
        L('                os.cp(toolchain_file, dest_file)')
        L('                print("=> Toolchain definition installed to: %s", user_toolchain_dir)')
        L('            end')
        L('        end')
    end

    L('    end)')

    -- ── on_download (custom) ──
    if ic.custom_download then
        L('')
        L('    on_download(function (package, opt)')
        L(format('        cprint("${green}[%s]${clear} Downloading %%s...", package:version_str())', label))
        L(format('        cprint("${green}[%s]${clear} File: %%s", path.filename(opt.url))', label))
        if ic.download_size then
            L(format('        cprint("${green}[%s]${clear} This is a large download (%s)")', label, ic.download_size))
        end
        L('')
        L('        import("net.http")')
        L('        import("utils.progress")')
        L('')
        L('        local downloadfile = opt.outputfile')
        L('        local filesize = nil')
        L('        local ok, errors = try { function()')
        L('            filesize = http.downloadsize(opt.url)')
        L('            return true')
        L('        end }')
        L('')
        L('        if filesize and filesize > 0 then')
        L(format('            cprint("${green}[%s]${clear} Download size: ${bright}%%.2f MB${clear}", filesize / 1024 / 1024)', label))
        L('            progress.show(opt.progress or 0, "${green}downloading${clear} %s", path.filename(opt.url))')
        L('            http.download(opt.url, downloadfile, {')
        L('                headers = opt.headers,')
        L('                progress = function (progress_info)')
        L('                    progress.show(progress_info, "${green}downloading${clear} %s", path.filename(opt.url))')
        L('                end')
        L('            })')
        L('        else')
        L(format('            cprint("${green}[%s]${clear} Downloading... (progress not available)")', label))
        L('            http.download(opt.url, downloadfile, {headers = opt.headers})')
        L('        end')
        L('')
        L(format('        cprint("${green}[%s]${clear} Download completed!")', label))
        L('')
        L('        local sourcedir = path.join(package:cachedir(), "source")')
        L('        os.mkdir(sourcedir)')
        L('        io.writefile(path.join(sourcedir, ".placeholder"), "")')
        L('')
        L('        return downloadfile')
        L('    end)')
    end

    -- ── on_install ──
    L('')
    local install_plats = ic.custom_download and '"@windows", "@linux", "@macosx"' or '"linux", "windows", "macosx"'
    L(format('    on_install(%s, function(package)', install_plats))
    L('        import("core.base.option")')
    L('')
    L(format('        cprint("${green}[%s]${clear} Installing %%s...", package:version_str())', label))

    if has_dmg then
        local dmg_pattern = ic.dmg_search_pattern
        L('')
        L('        if package:is_plat("macosx") then')
        L('            local originfile = package:originfile()')
        L('            if os.isfile(originfile) then')
        L('                local filesize = os.filesize(originfile)')
        L(format('                cprint("${green}[%s]${clear} DMG size: ${bright}%%.2f MB${clear}", filesize / 1024 / 1024)', label))
        L('            end')
        L('')
        L(format('            cprint("${green}[%s]${clear} Mounting DMG image...")', label))
        L('            local mountdir')
        L('            local result = os.iorunv("hdiutil", {"attach", package:originfile()})')
        L('            if result then')
        L('                for _, line in ipairs(result:split("\\n", {plain = true})) do')
        L('                    local pos = line:find("/Volumes", 1, true)')
        L('                    if pos then')
        L('                        mountdir = line:sub(pos):trim()')
        L('                        break')
        L('                    end')
        L('                end')
        L('            end')
        L('')
        L('            local function safe_detach()')
        L('                if mountdir and os.isdir(mountdir) then')
        L(format('                    cprint("${green}[%s]${clear} Unmounting DMG...")', label))
        L('                    try { function() os.execv("hdiutil", {"detach", mountdir, "-force"}) end }')
        L('                end')
        L('            end')
        L('')
        L('            if not mountdir or not os.isdir(mountdir) then')
        L('                raise("cannot mount DMG: %s", package:originfile())')
        L('            end')
        L(format('            cprint("${green}[%s]${clear} Mounted at: %%s", mountdir)', label))

        if dmg_pattern then
            -- dmg_search_pattern は文字列または配列を許容
            local patterns = type(dmg_pattern) == "table" and dmg_pattern or {dmg_pattern}
            L('')
            L(format('            cprint("${green}[%s]${clear} Looking for toolchain directory...")', label))
            L('            local toolchaindir')
            L('            for _, dir in ipairs(os.dirs(path.join(mountdir, "*"))) do')
            L('                local basename = path.basename(dir)')
            -- 複数パターンのいずれかにマッチすれば OK
            local conditions = {}
            for _, pat in ipairs(patterns) do
                table.insert(conditions, format('basename:find("%s")', pat))
            end
            L(format('                if %s then', table.concat(conditions, " or ")))
            L('                    toolchaindir = dir')
            L('                    break')
            L('                end')
            L('            end')
            L('            if not toolchaindir then')
            L('                safe_detach()')
            L('                raise("toolchain directory not found in DMG: %s", mountdir)')
            L('            end')
            L(format('            cprint("${green}[%s]${clear} Found: %%s", path.basename(toolchaindir))', label))
            L('')
            L(format('            cprint("${green}[%s]${clear} Copying toolchain files...")', label))
            L('            local copy_ok = try { function()')
            L('                local rsync_path = try { function() return os.iorun("which rsync") end }')
            L('                if rsync_path and rsync_path:trim() ~= "" then')
            L('                    os.vrunv("rsync", {"-ah", "--progress", toolchaindir .. "/", package:installdir() .. "/"})')
            L('                else')
            L('                    os.vexecv("bash", {"-c", format("cp -R %s/* %s", toolchaindir, package:installdir())})')
            L('                end')
            L('                return true')
            L('            end }')
        else
            L('')
            L(format('            cprint("${green}[%s]${clear} Copying files...")', label))
            L('            local copy_ok = try { function()')
            L('                os.cp(path.join(mountdir, "*"), package:installdir())')
            L('                return true')
            L('            end }')
        end

        L('')
        L('            safe_detach()')
        L('')
        L('            if not copy_ok then')
        L('                raise("Failed to copy files from DMG")')
        L('            end')
        L('        else')
    end

    -- Linux/Windows extraction (indent depends on has_dmg)
    if ic.custom_download then
        L(ei .. 'local cachedir = package:cachedir()')
        L(ei .. 'local originfile = nil')
        L(ei .. 'for _, file in ipairs(os.files(path.join(cachedir, "*.tar.xz"))) do')
        L(ei .. '    originfile = file')
        L(ei .. '    break')
        L(ei .. 'end')
        L(ei .. 'if not originfile then')
        L(ei .. '    for _, file in ipairs(os.files(path.join(cachedir, "*.zip"))) do')
        L(ei .. '        originfile = file')
        L(ei .. '        break')
        L(ei .. '    end')
        L(ei .. 'end')
        L(ei .. format('if not originfile or not os.isfile(originfile) then'))
        L(ei .. format('    raise("%s: Archive not found in cache: %%s", cachedir)', pkg_name))
        L(ei .. 'end')
    else
        L(ei .. 'local originfile = package:originfile()')
    end
    L(ei .. 'if os.isfile(originfile) then')
    L(ei .. '    local filesize = os.filesize(originfile)')
    L(ei .. format('    cprint("${green}[%s]${clear} Archive size: ${bright}%%.2f MB${clear}", filesize / 1024 / 1024)', label))
    L(ei .. 'end')
    L('')
    L(ei .. format('cprint("${green}[%s]${clear} Extracting toolchain files...")', label))
    L(ei .. 'if option.get("verbose") or option.get("diagnosis") then')

    if ic.custom_download then
        L(ei .. '    os.vrunv("tar", {"-xJvf", originfile, "-C", package:installdir(), "--strip-components=1"})')
        L(ei .. 'else')
        L(ei .. format('    cprint("${green}[%s]${clear} Extracting (this may take several minutes)...")', label))
        L(ei .. '    local has_pv = try { function() return os.iorun("which pv") end }')
        L(ei .. '    if has_pv and has_pv:trim() ~= "" then')
        L(ei .. '        os.vexecv("bash", {"-c", format("pv %s | tar -xJf - -C %s --strip-components=1", originfile, package:installdir())})')
        L(ei .. '    else')
        L(ei .. format('        io.write("[%s] Progress: ")', label))
        L(ei .. '        io.flush()')
        L(ei .. '        local tmpscript = os.tmpfile() .. ".sh"')
        -- Use nested string delimiters to avoid escaping issues
        L(ei .. '        io.writefile(tmpscript, format([=[')
        L('#!/bin/bash')
        L('tar -xJf "%s" -C "%s" --strip-components=1 &')
        L('TAR_PID=$!')
        L('while kill -0 $TAR_PID 2>/dev/null; do')
        L('    printf "."')
        L('    sleep 2')
        L('done')
        L('printf " done!\\n"')
        L(']=], originfile, package:installdir()))')
        L(ei .. '        os.vexecv("bash", {tmpscript})')
        L(ei .. '        os.rm(tmpscript)')
        L(ei .. '    end')
    else
        L(ei .. '    os.vrunv("tar", {"-xzvf", originfile, "-C", package:installdir(), "--strip-components=1"})')
        L(ei .. 'else')
        L(ei .. '    os.vrunv("tar", {"-xzf", originfile, "-C", package:installdir(), "--strip-components=1"})')
    end
    L(ei .. 'end')

    if has_dmg then
        L('        end')
    end

    -- chmod
    L('')
    L(format('        cprint("${green}[%s]${clear} Setting up toolchain binaries...")', label))
    L('        if not is_host("windows") then')
    L('            local bindir = path.join(package:installdir(), "bin")')
    L('            if os.isdir(bindir) then')
    L('                os.vrunv("chmod", {"-R", "+x", bindir})')
    L('            end')
    L('        end')

    -- verify
    if ic.bin_verify and #ic.bin_verify > 0 then
        L('')
        L(format('        cprint("${green}[%s]${clear} Verifying installation...")', label))
        L('        local bindir = path.join(package:installdir(), "bin")')
        local verify_bin = ic.bin_check or "gcc"
        L(format('        local exe = is_host("windows") and "%s.exe" or "%s"', verify_bin, verify_bin))
        L('        local exe_path = path.join(bindir, exe)')
        L('        if not os.isfile(exe_path) then')
        L(format('            raise("%s not found after installation: %%s", exe_path)', verify_bin))
        L('        end')
    end

    L('')
    L(format('        cprint("${green}[%s]${clear} Installation completed successfully!")', label))
    L(format('        cprint("${green}[%s]${clear} Toolchain installed to: ${bright}%%s${clear}", package:installdir())', label))
    L('    end)')

    -- ── on_test ──
    if ic.bin_verify and #ic.bin_verify > 0 then
        L('')
        L('    on_test(function (package)')
        local verify_bin = ic.bin_check or "gcc"
        L(format('        local exe = path.join(package:installdir(), "bin", "%s")', verify_bin))
        L('        if is_host("windows") then')
        L('            exe = exe .. ".exe"')
        L('        end')
        for _, cmd in ipairs(ic.bin_verify) do
            local parts = cmd:split("%s+")
            local args = {}
            for i = 2, #parts do
                table.insert(args, parts[i])
            end
            if #args > 0 then
                local args_str = table.concat(args, '", "')
                L(format('        os.vrunv(exe, {"%s"})', args_str))
            else
                L('        os.vrunv(exe, {"--version"})')
            end
        end
        L('    end)')
    end

    return lines
end
