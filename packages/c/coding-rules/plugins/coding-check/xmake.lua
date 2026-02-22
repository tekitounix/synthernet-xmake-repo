-- xmake coding-check plugin
-- Comprehensive code quality checks: format + lint + build
-- Replaces coding.style.ci with `xmake coding-check --ci`

task("coding-check")
    set_category("plugin")

    on_run(function ()
        import("core.base.option")
        import("core.base.task")
        import("lib.detect.find_program")

        local ci_mode = option.get("ci")

        print("=== Code Quality Check%s ===", ci_mode and " (CI)" or "")
        print("")

        local all_passed = true

        -- Step 1: Format check (dry-run in CI, apply in interactive)
        print("Step 1/3: Code formatting...")
        local format_ok = true
        local ok = try {
            function ()
                local clang_format = find_program("clang-format")
                if not clang_format then
                    print("  clang-format not found, skipping")
                    return true
                end
                if ci_mode then
                    task.run("coding-format", {["dry-run"] = true})
                else
                    task.run("coding-format", {})
                end
                return true
            end,
            catch {
                function (err)
                    print("  Format check failed: %s", tostring(err))
                    return false
                end
            }
        }
        if not ok then
            format_ok = false
            all_passed = false
        else
            print("  Format check passed")
        end
        print("")

        -- Step 2: Lint (compdb-based)
        print("Step 2/3: Static analysis...")
        local lint_ok = true
        ok = try {
            function ()
                local clang_tidy = find_program("clang-tidy")
                if not clang_tidy then
                    print("  clang-tidy not found, skipping")
                    return true
                end
                local lint_opts = {}
                if option.get("checks") then
                    lint_opts.checks = option.get("checks")
                end
                if option.get("changed") then
                    lint_opts.changed = true
                end
                task.run("lint", lint_opts)
                return true
            end,
            catch {
                function (err)
                    print("  Lint check failed: %s", tostring(err))
                    return false
                end
            }
        }
        if not ok then
            lint_ok = false
            all_passed = false
        else
            print("  Lint check passed")
        end
        print("")

        -- Step 3: Build check
        print("Step 3/3: Build integrity...")
        local build_ok = true
        if option.get("full") or ci_mode then
            ok = try {
                function ()
                    task.run("build", {})
                    return true
                end,
                catch {
                    function (err)
                        print("  Build failed: %s", tostring(err))
                        return false
                    end
                }
            }
            if not ok then
                build_ok = false
                all_passed = false
            else
                print("  Build passed")
            end
        else
            print("  Skipped (use --full or --ci for build check)")
        end
        print("")

        -- Summary
        print("=== Summary ===")
        if all_passed then
            print("All checks passed!")
        else
            if not format_ok then print("  FAIL: format") end
            if not lint_ok   then print("  FAIL: lint") end
            if not build_ok  then print("  FAIL: build") end
            os.exit(1)
        end
    end)

    set_menu {
        usage = "xmake coding-check [options]",
        description = "Run format + lint + build checks",
        options = {
            {nil, "ci",      "k",  nil, "CI mode (dry-run format + lint + build)"},
            {nil, "full",    "k",  nil, "Include build check"},
            {nil, "changed", "k",  nil, "Lint only git-changed files"},
            {'c', "checks",  "kv", nil, "Override clang-tidy checks"},
        }
    }
