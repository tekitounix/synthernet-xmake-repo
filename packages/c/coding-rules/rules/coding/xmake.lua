-- Coding style rules (project-root config reference)
-- Config files (.clang-format, .clang-tidy) are read from os.projectdir().
-- The project root is the single source of truth for all config.
--
-- Phase 7: coding.style before_build is removed (use `xmake format` / `xmake lint` instead).
-- Phase 7: coding.style.ci is removed (use `xmake check --ci` instead).
-- These rules are kept as no-ops for backward compatibility.

rule("coding.style")
    on_config(function (target)
        -- Point to project root config (single source of truth)
        local project_dir = os.projectdir()
        target:set("coding_style_config", path.join(project_dir, ".clang-format"))
        target:set("coding_style_tidy_config", path.join(project_dir, ".clang-tidy"))
    end)
    -- No before_build: use `xmake format` / `xmake lint` explicitly

rule("coding.style.ci")
    on_config(function (target)
        local project_dir = os.projectdir()
        target:set("coding_style_config", path.join(project_dir, ".clang-format"))
        target:set("coding_style_ci_mode", true)
    end)
    -- No before_build: use `xmake check --ci` explicitly