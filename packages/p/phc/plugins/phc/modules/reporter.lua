-- plugins/phc/modules/reporter.lua
--
-- 検査結果の出力 — stdout (色付き) + JSON ファイル
-- xmake import() は非ローカル関数をエクスポートする。

import("core.base.json")

-- ── stdout 出力 ──────────────────────────────────────────────────

function print_link_report(report)
    cprint("${bright}[PHC] Link Check Report${clear}")
    cprint("")

    for _, r in ipairs(report.results) do
        local icon = r.status == "ok" and "${green}✓" or "${red}✗"
        cprint("  %s %s %s/%s${clear}  %s", icon, r.package, r.version, r.platform, r.url)
        if r.status ~= "ok" then
            cprint("    ${dim}→ %s${clear}", r.error or "unknown error")
        end
    end

    cprint("")
    cprint("  Summary: %d/%d OK", report.summary.ok, report.summary.total)
end

function print_update_report(report)
    cprint("${bright}[PHC] Update Check Report${clear}")
    cprint("")

    if report.has_updates then
        for _, u in ipairs(report.updates) do
            if #u.new_versions > 0 then
                cprint("  ${cyan}%s${clear} (current: %s)", u.package, u.current_latest)
                for _, v in ipairs(u.new_versions) do
                    cprint("    ${green}+ %s${clear}", v)
                end
            end
        end
    else
        cprint("  ${green}All packages up to date.${clear}")
    end
end

function print_validation_report(issues)
    cprint("${bright}[PHC] Validation Report${clear}")
    cprint("")

    if #issues == 0 then
        cprint("  ${green}✓ All packages consistent.${clear}")
        return
    end

    for _, issue in ipairs(issues) do
        local color = issue.severity == "error" and "red" or "yellow"
        cprint("  ${%s}[%s]${clear} %s: %s",
               color, issue.severity:upper(), issue.package, issue.message)
    end

    local errors   = 0
    local warnings = 0
    for _, issue in ipairs(issues) do
        if issue.severity == "error" then errors = errors + 1
        else warnings = warnings + 1 end
    end

    cprint("")
    cprint("  Summary: %d error(s), %d warning(s)", errors, warnings)
end

-- ── JSON 出力 ────────────────────────────────────────────────────

function save_json(filepath, data)
    local content = json.encode(data)
    io.writefile(filepath, content)
    cprint("${dim}Report saved to %s${clear}", filepath)
end
