-- Tasks.json generator for VSCode build tasks.
-- Generates build/clean/flash tasks for the default embedded target
-- while preserving user-defined tasks.

import("core.base.json")
import("json_file")

-- Managed task labels (regenerated on every build).
local managed_labels = {
    ["Build (Release)"] = true,
    ["Build (Debug)"]   = true,
    ["Clean"]           = true,
    ["Build & Flash"]   = true,
    ["Start Renode"]    = true,
}

local function is_managed(label)
    return managed_labels[label] == true
end

-- Generate or update .vscode/tasks.json.
--
-- @param vscode_dir      Path to .vscode directory
-- @param default_target  Name of the default embedded target
-- @param renode_info     Optional table { resc_path = "...", renode_cmd = "..." } for Renode support
function generate(vscode_dir, default_target, renode_info)
    local tasks_file = path.join(vscode_dir, "tasks.json")

    -- Load existing file, keeping only user-defined tasks
    local tasks = json_file.load_and_filter(tasks_file, "tasks", is_managed, "label")

    -- Build managed tasks
    local managed_tasks = {
        {
            label = "Build (Release)",
            type = "shell",
            command = "xmake config -m release && xmake build " .. default_target,
            group = "build",
            problemMatcher = "$gcc"
        },
        {
            label = "Build (Debug)",
            type = "shell",
            command = "xmake config -m debug && xmake build " .. default_target,
            group = "build",
            problemMatcher = "$gcc"
        },
        {
            label = "Clean",
            type = "shell",
            command = "xmake",
            args = { "clean", default_target },
            problemMatcher = {}
        },
        {
            label = "Build & Flash",
            type = "shell",
            command = "xmake config -m release && xmake build "
                      .. default_target .. " && xmake flash -t " .. default_target,
            group = "build",
            problemMatcher = "$gcc"
        },
    }

    -- Append managed tasks after user tasks
    for _, t in ipairs(managed_tasks) do
        table.insert(tasks.tasks, t)
    end

    -- Add Renode background task if supported
    if renode_info and renode_info.resc_path then
        local renode_task = {
            label = "Start Renode",
            type = "shell",
            command = (renode_info.renode_cmd or "renode") .. " --disable-xwt ${workspaceFolder}/" .. renode_info.resc_path,
            dependsOn = "Build (Debug)",
            isBackground = true,
            problemMatcher = {
                pattern = {
                    regexp = "^$"
                },
                background = {
                    activeOnStart = true,
                    beginsPattern = ".*",
                    endsPattern = "GDB server with all CPUs started"
                }
            }
        }
        table.insert(tasks.tasks, renode_task)
    end

    json_file.save(tasks_file, tasks)
    print("tasks.json updated!")
end
