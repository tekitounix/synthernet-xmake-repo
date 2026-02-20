-- Force-regenerate the normalized compile_commands.json for clangd.
--
-- This plugin clears the embedded.compdb dependency cache and triggers a build,
-- which causes the compdb rule to regenerate unconditionally.
-- Already-compiled files are not recompiled — only the compdb generation runs.
--
-- Usage: xmake compdb [target]

task("compdb")
    set_category("plugin")
    set_menu {
        usage = "xmake compdb [target]",
        description = "Force-regenerate normalized compile_commands.json for clangd",
        options = {
            {nil, "target", "v", nil, "Target name (any target works — compdb covers all targets)"}
        }
    }
    on_run(function ()
        import("core.project.config")
        import("core.base.option")

        config.load()

        -- Clear dependency cache so embedded.compdb rule runs unconditionally
        local dependfile = path.join(config.builddir(), ".gens", "rules", "embedded.compdb.d")
        os.rm(dependfile)

        -- Trigger build (compdb rule runs in after_build hook)
        local target = option.get("target")
        if target then
            os.execv("xmake", {"build", target})
        else
            os.execv("xmake", {"build"})
        end
    end)
