-- Espressif RISC-V toolchain definition
toolchain("riscv32-esp")
    set_kind("cross")
    set_description("Espressif RISC-V GCC toolchain (riscv32-esp-elf)")

    -- Toolset definitions
    set_toolset("cc", "riscv32-esp-elf-gcc")
    set_toolset("cxx", "riscv32-esp-elf-g++")
    set_toolset("ld", "riscv32-esp-elf-g++")
    set_toolset("sh", "riscv32-esp-elf-g++")
    set_toolset("ar", "riscv32-esp-elf-ar")
    set_toolset("strip", "riscv32-esp-elf-strip")
    set_toolset("ranlib", "riscv32-esp-elf-ranlib")
    set_toolset("objcopy", "riscv32-esp-elf-objcopy")
    set_toolset("as", "riscv32-esp-elf-gcc")

    on_load(function (toolchain)
        -- Try official approach first using toolchain:packages()
        local packages = toolchain:packages()
        if packages then
            for _, pkg in ipairs(packages) do
                if pkg:name() == "riscv32-esp" then
                    local bindir = path.join(pkg:installdir(), "bin")
                    if os.isdir(bindir) then
                        toolchain:set("bindir", bindir)
                        return
                    end
                end
            end
        end

        -- Fallback: Get package installation directory directly
        -- This is needed when toolchain is used without package specification
        -- e.g., in embedded rule or set_toolchains("riscv32-esp") without @riscv32-esp
        import("core.base.global")
        local pkg_path = path.join(global.directory(), "packages/r/riscv32-esp")
        if os.isdir(pkg_path) then
            local versions = os.dirs(path.join(pkg_path, "*"))
            if #versions > 0 then
                table.sort(versions)
                local latest = versions[#versions]
                local installs = os.dirs(path.join(latest, "*"))
                if #installs > 0 then
                    local install_dir = installs[1]
                    local bindir = path.join(install_dir, "bin")
                    if os.isdir(bindir) then
                        toolchain:set("bindir", bindir)
                    end
                end
            end
        end
    end)

    on_check(function (toolchain)
        return import("lib.detect.find_tool")("riscv32-esp-elf-gcc")
    end)
toolchain_end()
