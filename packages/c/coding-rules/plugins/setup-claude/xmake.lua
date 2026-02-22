-- xmake setup-claude plugin
-- Deploys Claude Code hooks, rules, and MCP server configuration from packages.
--
-- This plugin handles Stage 2 of the package deployment:
--   Stage 1 (on_load): packages -> ~/.xmake/  (automatic)
--   Stage 2 (this):    ~/.xmake/ -> .claude/   (manual, one-time)
--
-- Discovery:
--   Dynamically scans ~/.xmake/rules/*/claude/ for packages to deploy.
--   No hardcoded package names — any package with a claude/ directory
--   is automatically picked up.
--
-- What it does:
--   1. Scan ~/.xmake/rules/*/claude/ for deployable packages
--   2. Copy hooks/skills/agents/rules to .claude/
--   3. Parse hook metadata comments for settings.json registration
--   4. Register MCP servers from mcp/*.py in .mcp.json
--   5. Update .gitignore for package-managed files
--
-- Hook metadata format (in hook .py files, lines 1-10):
--   # claude-hook: event=PostToolUse matcher=Edit|Write
--   # claude-hook: event=SessionStart
--
-- Usage: xmake setup-claude [--force]

task("setup-claude")
    set_category("plugin")

    on_run(function ()
        import("core.base.option")
        import("core.base.global")
        import("core.base.json")

        local project_dir = os.projectdir()
        local global_dir = global.directory()
        local force = option.get("force")

        -- Import shared json_pretty module from coding-rules scripts
        local script_dir = path.join(global_dir, "rules", "coding", "scripts")
        local json_pretty = import("json_pretty", {rootdir = script_dir})

        -- Helper: sync files from src_dir to dest_dir
        local function sync_files(src_dir, dest_dir, pattern)
            if not os.isdir(src_dir) then return 0 end
            local count = 0
            local files = os.files(path.join(src_dir, pattern or "**"))
            for _, f in ipairs(files) do
                local rel = path.relative(f, src_dir)
                local dest = path.join(dest_dir, rel)
                os.mkdir(path.directory(dest))
                io.writefile(dest, io.readfile(f))
                count = count + 1
            end
            return count
        end

        -- Helper: load JSON file (returns table, creates empty if not found)
        local function load_json(filepath)
            if os.isfile(filepath) then
                local content = io.readfile(filepath)
                -- Strip comments for JSONC support
                local cleaned = content:gsub("//[^\n]*", "")
                local result = try { function () return json.decode(cleaned) end }
                if result then return result end
            end
            return {}
        end

        -- Helper: save JSON file (pretty-printed, unescaped slashes)
        local function save_json(filepath, data)
            io.writefile(filepath, json_pretty.encode_clean(data))
        end

        -- Helper: parse hook metadata from a script file.
        -- Reads first 10 lines looking for:
        --   # claude-hook: event=<Event> [matcher=<Matcher>]
        -- Returns list of {event, matcher (optional), script_path, filename}
        local function parse_hook_metadata(script_path)
            local hooks = {}
            local content = io.readfile(script_path)
            if not content then return hooks end

            local filename = path.filename(script_path)
            -- Remove .py extension for prefix matching
            local prefix = filename:gsub("%.py$", "")

            local line_num = 0
            for line in content:gmatch("[^\r\n]+") do
                line_num = line_num + 1
                if line_num > 10 then break end

                local meta = line:match("^#%s*claude%-hook:%s*(.+)$")
                if meta then
                    local event = meta:match("event=(%S+)")
                    local matcher = meta:match("matcher=(%S+)")
                    if event then
                        table.insert(hooks, {
                            event = event,
                            matcher = matcher,
                            filename = filename,
                            prefix = prefix,
                        })
                    end
                end
            end
            return hooks
        end

        local total = 0
        local claude_dir = path.join(project_dir, ".claude")

        -- Deployable subdirectory types: source subdir -> .claude/ destination
        local deploy_dirs = {"hooks", "skills", "agents", "rules"}

        -- Track all deployed files for .gitignore generation
        local deployed_patterns = {}
        -- Track all parsed hook definitions
        local managed_hooks = {}
        -- Track discovered MCP servers: {name, script_path}
        local mcp_servers = {}

        print("=== Claude Code Setup ===")
        print("")

        -- =================================================================
        -- Phase 1: Dynamic scan of ~/.xmake/rules/*/claude/
        -- =================================================================
        local rules_base = path.join(global_dir, "rules")
        local pkg_dirs = os.dirs(path.join(rules_base, "*", "claude"))
        if not pkg_dirs then pkg_dirs = {} end

        -- Sort for deterministic output
        table.sort(pkg_dirs)

        for _, claude_pkg_dir in ipairs(pkg_dirs) do
            -- Extract package name: ~/.xmake/rules/<pkg_name>/claude
            local pkg_name = path.basename(path.directory(claude_pkg_dir))

            print("Package: %s", pkg_name)

            -- Deploy each subdirectory type
            for _, subdir in ipairs(deploy_dirs) do
                local src = path.join(claude_pkg_dir, subdir)
                if os.isdir(src) then
                    local dest = path.join(claude_dir, subdir)
                    local n = sync_files(src, dest)
                    total = total + n
                    print("  %s: %d file(s)", subdir, n)

                    -- Collect gitignore patterns for deployed files
                    local files = os.files(path.join(src, "**"))
                    for _, f in ipairs(files) do
                        local rel = path.relative(f, src)
                        table.insert(deployed_patterns,
                            ".claude/" .. subdir .. "/" .. rel)
                    end
                end
            end

            -- Parse hook metadata from deployed hooks
            local hooks_src = path.join(claude_pkg_dir, "hooks")
            if os.isdir(hooks_src) then
                local hook_files = os.files(path.join(hooks_src, "*.py"))
                for _, hf in ipairs(hook_files) do
                    local metas = parse_hook_metadata(hf)
                    for _, m in ipairs(metas) do
                        table.insert(managed_hooks, m)
                    end
                end
            end

            -- Discover MCP servers from mcp/*.py
            local mcp_dir = path.join(claude_pkg_dir, "mcp")
            if os.isdir(mcp_dir) then
                local mcp_files = os.files(path.join(mcp_dir, "*.py"))
                for _, mf in ipairs(mcp_files) do
                    table.insert(mcp_servers, {
                        name = pkg_name,
                        script = mf,
                    })
                end
            end

            print("")
        end

        if #pkg_dirs == 0 then
            print("No packages found in %s/*/claude/", rules_base)
            print("Run 'xmake dev-sync' first to propagate packages.")
            print("")
        end

        -- =================================================================
        -- Phase 2: settings.json — merge hook entries from metadata
        -- =================================================================
        local settings_path = path.join(claude_dir, "settings.json")
        os.mkdir(claude_dir)
        local settings = load_json(settings_path)
        if not settings.hooks then
            settings.hooks = {}
        end

        for _, hook_def in ipairs(managed_hooks) do
            local event = hook_def.event
            if not settings.hooks[event] then
                settings.hooks[event] = {}
            end

            local command = format(
                'python3 "$CLAUDE_PROJECT_DIR"/.claude/hooks/%s',
                hook_def.filename)

            local hook_entry = {
                hooks = {
                    {type = "command", command = command}
                }
            }
            if hook_def.matcher then
                hook_entry.matcher = hook_def.matcher
            end

            -- Check if this hook already exists (by filename prefix)
            local found = false
            for _, existing in ipairs(settings.hooks[event]) do
                if existing.hooks then
                    for _, h in ipairs(existing.hooks) do
                        if h.command and h.command:find(hook_def.prefix, 1, true) then
                            -- Update existing entry
                            h.command = command
                            if hook_def.matcher then
                                existing.matcher = hook_def.matcher
                            end
                            found = true
                            break
                        end
                    end
                end
                if found then break end
            end

            if not found then
                table.insert(settings.hooks[event], hook_entry)
            end
        end

        save_json(settings_path, settings)
        print("Updated: .claude/settings.json (%d hook entries)", #managed_hooks)

        -- =================================================================
        -- Phase 3: .mcp.json — register MCP servers
        -- =================================================================
        local mcp_path = path.join(project_dir, ".mcp.json")
        local mcp = load_json(mcp_path)
        if not mcp.mcpServers then
            mcp.mcpServers = {}
        end

        -- Find python3 executable (prefer pyenv for consistent environment)
        local python3 = "python3"
        local pyenv_python = path.join(os.getenv("HOME") or "~", ".pyenv", "versions")
        if os.isdir(pyenv_python) then
            local versions = os.dirs(path.join(pyenv_python, "*"))
            if versions and #versions > 0 then
                table.sort(versions)
                local latest = versions[#versions]
                local py = path.join(latest, "bin", "python3")
                if os.isfile(py) then
                    python3 = py
                end
            end
        end

        for _, server in ipairs(mcp_servers) do
            mcp.mcpServers[server.name] = {
                type = "stdio",
                command = python3,
                args = {server.script},
            }
            print("Added MCP server: %s -> %s", server.name, server.script)
        end

        save_json(mcp_path, mcp)
        print("Updated: .mcp.json")
        print("")

        -- =================================================================
        -- Phase 4: .gitignore — auto-generate from deployed files
        -- =================================================================
        local gitignore_path = path.join(project_dir, ".gitignore")
        local gitignore_content = ""
        if os.isfile(gitignore_path) then
            gitignore_content = io.readfile(gitignore_path)
        end

        local header = "# Package-managed Claude files (auto-generated by xmake setup-claude)"

        -- Build deduplicated pattern list using directory-level globs
        -- e.g. .claude/hooks/coding_* instead of individual files
        local gitignore_globs = {}
        local seen_globs = {}
        for _, deployed in ipairs(deployed_patterns) do
            -- Extract directory and first path component for glob pattern
            -- .claude/hooks/coding_post_edit_format.py -> .claude/hooks/coding_*
            -- .claude/skills/run-tests/SKILL.md -> .claude/skills/run-tests/
            local dir = path.directory(deployed)
            local fname = path.filename(deployed)

            local glob
            -- For files directly under a deploy dir (hooks, rules, agents),
            -- use prefix-based glob: coding_* / embedded_*
            local parts = dir:split("/")
            if #parts == 2 then
                -- .claude/<subdir>/<file> — use filename prefix up to first _
                local prefix = fname:match("^([^_]+_)")
                if prefix then
                    glob = dir .. "/" .. prefix .. "*"
                else
                    glob = deployed
                end
            else
                -- Nested directories (e.g. .claude/skills/run-tests/SKILL.md)
                -- Use the subdirectory as the glob target
                glob = parts[1] .. "/" .. parts[2] .. "/" .. parts[3] .. "/"
            end

            if not seen_globs[glob] then
                seen_globs[glob] = true
                table.insert(gitignore_globs, glob)
            end
        end

        -- Sort for deterministic output
        table.sort(gitignore_globs)

        -- Remove old auto-generated section if present
        local section_start = gitignore_content:find(header, 1, true)
        if section_start then
            -- Find the end of the managed section (next blank line or EOF)
            local section_end = gitignore_content:find("\n\n", section_start)
            if section_end then
                gitignore_content = gitignore_content:sub(1, section_start - 1)
                    .. gitignore_content:sub(section_end + 1)
            else
                -- Section goes to end of file — trim trailing whitespace
                gitignore_content = gitignore_content:sub(1, section_start - 1)
            end
            -- Remove trailing newlines from the cut
            gitignore_content = gitignore_content:gsub("\n+$", "\n")
        end

        -- Build new section
        if #gitignore_globs > 0 then
            local lines = {header}
            for _, g in ipairs(gitignore_globs) do
                table.insert(lines, g)
            end

            local section = "\n" .. table.concat(lines, "\n") .. "\n"
            io.writefile(gitignore_path, gitignore_content .. section)
            print("Updated: .gitignore (%d patterns)", #gitignore_globs)
        end

        print("")
        print("=== Setup Complete: %d files deployed from %d packages ===", total, #pkg_dirs)
        print("")
        print("Next steps:")
        print("  1. Review .claude/settings.json hook entries")
        print("  2. Review .mcp.json server entries")
        print("  3. Restart Claude Code to pick up new hooks")
    end)

    set_menu {
        usage = "xmake setup-claude [options]",
        description = "Deploy Claude Code hooks, rules, and MCP config from packages",
        options = {
            {nil, "force", "k", nil, "Force overwrite all files"},
        }
    }
