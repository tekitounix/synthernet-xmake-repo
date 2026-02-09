-- plugins/phc/xmake.lua
--
-- Package Health Check (PHC) — xmake プラグイン CLI エントリポイント
--
-- 使用例:
--   xmake phc check-links                         # 全パッケージのリンク検証
--   xmake phc check-links -p clang-arm            # 特定パッケージ
--   xmake phc check-updates -o report.json        # 更新検知 + JSON 出力
--   xmake phc validate                            # registry ↔ xmake.lua 整合性
--   xmake phc generate                            # xmake.lua 生成
--   xmake phc generate -p clang-arm --dry-run     # 差分表示のみ
--   xmake phc update-package -p gcc-arm            # 新バージョン自動追加
--   xmake phc update-package -p renode --target-version 1.16.1
--

task("phc")
    set_category("plugin")

    on_run(function ()
        import("core.base.option")
        import("modules.registry")
        import("modules.checker")
        import("modules.validator")
        import("modules.reporter")
        import("modules.generator")
        import("modules.updater")

        local command = option.get("command")
        if not command then
            cprint("${bright}Package Health Check (PHC)${clear}")
            cprint("")
            cprint("Usage: xmake phc <command> [options]")
            cprint("")
            cprint("Commands:")
            cprint("  check-links     Check download link availability")
            cprint("  check-updates   Detect new upstream versions")
            cprint("  validate        Verify registry ↔ xmake.lua consistency")
            cprint("  generate        Generate xmake.lua from packages.lua")
            cprint("  update-package  Add new upstream versions (download + SHA256)")
            cprint("")
            cprint("Options:")
            cprint("  -p, --package <name>      Check specific package only")
            cprint("  -o, --output <file>       Write JSON report to file")
            cprint("  -r, --registry <path>     Path to packages.lua")
            cprint("      --packages-dir <dir>  Path to packages/ directory (for validate/generate)")
            cprint("      --dry-run             Show diff without writing (for generate)")
            cprint("      --target-version <v>  Target version (for update-package)")
            cprint("      --force               Force re-download even if version exists")
            return
        end

        -- レジストリパス解決（優先順位: -r 引数 > scriptdir > xmake-repo）
        local reg_path = option.get("registry")
        if not reg_path then
            -- 1. プラグイン自身のディレクトリ内 (インストール後はここにコピー済み)
            local candidate = path.join(os.scriptdir(), "registry", "packages.lua")
            if os.isfile(candidate) then
                reg_path = candidate
            end
        end
        if not reg_path then
            -- 2. ソースツリー: plugins/phc/ → (2つ上) → phc/ → registry/
            local pkg_root = path.directory(path.directory(os.scriptdir()))
            local candidate = path.join(pkg_root, "registry", "packages.lua")
            if os.isfile(candidate) then
                reg_path = candidate
            end
        end
        if not reg_path then
            -- 3. プロジェクト内 xmake-repo
            local candidate = path.join(os.projectdir(),
                "xmake-repo", "synthernet", "packages", "p", "phc",
                "registry", "packages.lua")
            if os.isfile(candidate) then
                reg_path = candidate
            end
        end
        if not reg_path then
            raise("registry not found. Specify with: -r /path/to/packages.lua")
        end

        cprint("${dim}registry: %s${clear}", reg_path)
        local reg = registry.load(reg_path)
        local pkg_filter = option.get("package")
        local output = option.get("output")

        -- ── check-links ─────────────────────────────────────────
        if command == "check-links" then
            cprint("${bright}[PHC]${clear} Checking download links...")
            cprint("")
            local report = checker.check_links(reg, pkg_filter)

            if output then
                reporter.save_json(output, report)
            end

            cprint("")
            if report.summary.fail > 0 then
                cprint("${red}FAIL${clear}: %d/%d links broken", report.summary.fail, report.summary.total)
                raise("broken links detected")
            else
                cprint("${green}OK${clear}: all %d links valid", report.summary.total)
            end

        -- ── check-updates ───────────────────────────────────────
        elseif command == "check-updates" then
            cprint("${bright}[PHC]${clear} Checking upstream versions...")
            cprint("")
            local report = checker.check_updates(reg, pkg_filter)

            if output then
                reporter.save_json(output, report)
            end

            cprint("")
            if report.has_updates then
                local count = 0
                for _, u in ipairs(report.updates) do
                    count = count + #u.new_versions
                end
                cprint("${yellow}UPDATES${clear}: %d new version(s) found", count)
            else
                cprint("${green}OK${clear}: all packages up to date")
            end

        -- ── validate ────────────────────────────────────────────
        elseif command == "validate" then
            cprint("${bright}[PHC]${clear} Validating registry ↔ xmake.lua...")
            cprint("")
            local packages_dir = option.get("packages-dir")
            if not packages_dir then
                packages_dir = path.join(os.projectdir(),
                    "xmake-repo", "synthernet", "packages")
            end

            local issues = validator.validate(reg, packages_dir)
            reporter.print_validation_report(issues)

            if output then
                reporter.save_json(output, {issues = issues})
            end

            local has_errors = false
            for _, issue in ipairs(issues) do
                if issue.severity == "error" then has_errors = true; break end
            end
            if has_errors then
                raise("validation failed")
            end

        -- ── generate ───────────────────────────────────────────
        elseif command == "generate" then
            cprint("${bright}[PHC]${clear} Generating xmake.lua from registry...")
            cprint("")

            if reg.schema_version() < 2 then
                raise("generate requires schema_version >= 2 (current: %d)", reg.schema_version())
            end

            local packages_dir = option.get("packages-dir")
            if not packages_dir then
                packages_dir = path.join(os.projectdir(),
                    "xmake-repo", "synthernet", "packages")
            end

            local dry_run = option.get("dry-run")
            local pkg_names = reg.filter(pkg_filter)
            local generated = 0
            local unchanged = 0

            for _, pkg_name in ipairs(pkg_names) do
                local config = reg.package_config(pkg_name)
                if not config.install then
                    cprint("  ${dim}skip${clear} %s (no install template)", pkg_name)
                    goto continue_gen
                end

                local content = generator.generate(pkg_name, config)
                local first_char = pkg_name:sub(1, 1)
                local target_path = path.join(packages_dir, first_char, pkg_name, "xmake.lua")

                if dry_run then
                    if os.isfile(target_path) then
                        local existing = io.readfile(target_path)
                        if existing == content .. "\n" or existing == content then
                            cprint("  ${green}✓${clear} %s — no changes", pkg_name)
                            unchanged = unchanged + 1
                        else
                            cprint("  ${yellow}~${clear} %s — would be updated:", pkg_name)
                            cprint("    target: %s", target_path)
                            generated = generated + 1
                        end
                    else
                        cprint("  ${yellow}+${clear} %s — would be created:", pkg_name)
                        cprint("    target: %s", target_path)
                        generated = generated + 1
                    end
                else
                    os.mkdir(path.directory(target_path))
                    io.writefile(target_path, content .. "\n")
                    cprint("  ${green}✓${clear} %s → %s", pkg_name, target_path)
                    generated = generated + 1
                end

                ::continue_gen::
            end

            cprint("")
            if dry_run then
                cprint("${dim}dry-run:${clear} %d would change, %d unchanged", generated, unchanged)
            else
                cprint("${green}OK${clear}: %d package(s) generated", generated)
            end

        -- ── update-package ─────────────────────────────────────
        elseif command == "update-package" then
            cprint("${bright}[PHC]${clear} Updating packages...")
            cprint("")

            if reg.schema_version() < 2 then
                raise("update-package requires schema_version >= 2 (current: %d)", reg.schema_version())
            end

            if not pkg_filter then
                raise("update-package requires -p <package> to specify which package to update")
            end

            local target_version = option.get("target-version")
            local force = option.get("force")

            local result = updater.update_package(reg, pkg_filter, {
                version = target_version,
                force = force,
            })

            if result.status == "success" then
                -- packages.lua に書き込む
                cprint("")
                cprint("  ${dim}updating packages.lua...${clear}")
                updater.apply_update(reg, pkg_filter, result, reg_path)
                cprint("  ${green}✓${clear} packages.lua updated")

                -- xmake.lua を再生成
                local packages_dir = option.get("packages-dir")
                if not packages_dir then
                    packages_dir = path.join(os.projectdir(),
                        "xmake-repo", "synthernet", "packages")
                end

                -- registry を再ロード（更新後のデータ）
                local updated_reg = registry.load(reg_path)
                local updated_config = updated_reg.package_config(pkg_filter)
                if updated_config.install then
                    local content = generator.generate(pkg_filter, updated_config)
                    local first_char = pkg_filter:sub(1, 1)
                    local target_path = path.join(packages_dir, first_char, pkg_filter, "xmake.lua")
                    os.mkdir(path.directory(target_path))
                    io.writefile(target_path, content .. "\n")
                    cprint("  ${green}✓${clear} %s/xmake.lua regenerated", pkg_filter)
                end

                -- validate
                cprint("")
                cprint("  ${dim}validating...${clear}")
                local issues = validator.validate(updated_reg, packages_dir)
                local has_errors = false
                for _, issue in ipairs(issues) do
                    if issue.severity == "error" then has_errors = true; break end
                end
                if has_errors then
                    reporter.print_validation_report(issues)
                    raise("validation failed after update")
                end
                cprint("  ${green}✓${clear} validation passed")

                cprint("")
                local ver_count = #result.versions
                cprint("${green}OK${clear}: %d version(s) added to %s", ver_count, pkg_filter)

                if output then
                    reporter.save_json(output, result)
                end
            elseif result.status == "up_to_date" then
                cprint("")
                cprint("${green}OK${clear}: %s is up to date", pkg_filter)
            elseif result.status == "skipped" then
                cprint("")
                cprint("${dim}SKIPPED${clear}: %s (%s)", pkg_filter, result.reason or "")
            else
                cprint("")
                cprint("${red}ERROR${clear}: %s — %s", pkg_filter, result.reason or "unknown error")
                raise("update failed")
            end

        else
            raise("unknown subcommand: %s (expected: check-links, check-updates, validate, generate, update-package)", command)
        end
    end)

    set_menu {
        usage = "xmake phc [options] <command>",
        description = "Package Health Check — monitor download links & upstream versions",
        options = {
            {'p', "package",      "kv", nil, "Check specific package only"},
            {'o', "output",       "kv", nil, "Write JSON report to file"},
            {'r', "registry",     "kv", nil, "Path to packages.lua"},
            {nil, "packages-dir", "kv", nil, "Path to packages/ directory (for validate/generate)"},
            {'n', "dry-run",     "k",  nil, "Show diff without writing (for generate)"},
            {nil, "target-version", "kv", nil, "Target version (for update-package)"},
            {nil, "force",       "k",  nil, "Force re-download even if version exists"},
            {nil, "command",      "v",  nil, "Subcommand: check-links, check-updates, validate, generate, update-package"},
        }
    }
task_end()
