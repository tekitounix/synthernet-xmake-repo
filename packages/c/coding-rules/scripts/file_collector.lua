-- file_collector.lua — 共有ファイル収集ロジック
-- lint / format / check プラグインで共用する。
-- coding-rules パッケージの scripts/ に配置。
--
-- Usage:
--   import("core.base.global")
--   local script_dir = path.join(global.directory(), "rules", "coding", "scripts")
--   local collector = import("file_collector", {rootdir = script_dir})
--   collector.init()

-- C/C++ ソース拡張子
source_extensions = {".cc", ".cpp", ".c"}
header_extensions = {".hh", ".hpp", ".h"}
all_extensions = {".cc", ".cpp", ".c", ".hh", ".hpp", ".h"}

-- デフォルト除外パターン（パス部分一致）
local default_exclude_patterns = {
    "/build/",
    "/.xmake/",
}

-- デフォルトスキャンディレクトリ（プロジェクトルートからの相対パス）
-- 空テーブル = プロジェクトルート直下を再帰スキャン
local default_scan_dirs = {}

-- Runtime state
exclude_patterns = default_exclude_patterns
default_scan_dirs_rt = default_scan_dirs
_initialized = false

--- 設定を初期化
function init()
    exclude_patterns = default_exclude_patterns
    default_scan_dirs_rt = default_scan_dirs
    _initialized = true
end

--- パスが除外対象かチェック
---@param filepath string 絶対パス
---@return boolean
function is_excluded(filepath)
    if not _initialized then
        exclude_patterns = default_exclude_patterns
    end
    for _, pat in ipairs(exclude_patterns) do
        if filepath:find(pat, 1, true) then
            return true
        end
    end
    return false
end

--- 拡張子がソースファイルかチェック
---@param filepath string
---@param extensions? table 拡張子リスト（デフォルト: source_extensions）
---@return boolean
function has_extension(filepath, extensions)
    extensions = extensions or source_extensions
    for _, ext in ipairs(extensions) do
        if filepath:sub(-#ext) == ext then
            return true
        end
    end
    return false
end

--- カンマ区切りファイルリストをパースして絶対パスリストを返す
---@param files_str string カンマ区切りファイルパス
---@param project_dir string プロジェクトルート
---@return table files 絶対パスリスト
function from_explicit(files_str, project_dir)
    local files = {}
    local seen = {}
    for file in files_str:gmatch("[^,]+") do
        file = file:match("^%s*(.-)%s*$")  -- trim
        if not path.is_absolute(file) then
            file = path.join(project_dir, file)
        end
        if not seen[file] then
            table.insert(files, file)
            seen[file] = true
        end
    end
    return files
end

--- git diff で変更されたファイルを収集
---@param project_dir string プロジェクトルート
---@param opts? table {extensions: table, filter_fn: function(file)->bool}
---@return table files 絶対パスリスト
function from_git_changed(project_dir, opts)
    opts = opts or {}
    local extensions = opts.extensions or source_extensions
    local filter_fn = opts.filter_fn

    local files = {}
    local seen = {}

    local function process_output(outdata)
        if not outdata then return end
        for line in outdata:gmatch("[^\r\n]+") do
            if has_extension(line, extensions) then
                local abs = path.join(project_dir, line)
                if not seen[abs] and (not filter_fn or filter_fn(abs)) then
                    table.insert(files, abs)
                    seen[abs] = true
                end
            end
        end
    end

    -- Scan dirs for git diff filter
    local scan_dirs = default_scan_dirs_rt
    if #scan_dirs > 0 then
        -- Build git pathspec list from scan dirs
        local pathspecs = {}
        for _, d in ipairs(scan_dirs) do
            table.insert(pathspecs, d .. "/")
        end

        -- Working tree changes
        local args1 = {"diff", "--name-only", "--"}
        for _, p in ipairs(pathspecs) do table.insert(args1, p) end
        local out1 = os.iorunv("git", args1)
        process_output(out1)

        -- Staged changes
        local args2 = {"diff", "--cached", "--name-only", "--"}
        for _, p in ipairs(pathspecs) do table.insert(args2, p) end
        local out2 = os.iorunv("git", args2)
        process_output(out2)
    else
        -- No scan dirs configured — scan all tracked files
        local out1 = os.iorunv("git", {"diff", "--name-only"})
        process_output(out1)
        local out2 = os.iorunv("git", {"diff", "--cached", "--name-only"})
        process_output(out2)
    end

    return files
end

--- ディレクトリを再帰スキャンしてファイルを収集
---@param project_dir string プロジェクトルート
---@param opts? table {dirs: table, extensions: table, target: string}
---@return table files 絶対パスリスト
function from_scan(project_dir, opts)
    opts = opts or {}
    local extensions = opts.extensions or all_extensions
    local scan_dirs = opts.dirs or default_scan_dirs_rt

    -- ターゲット指定時はディレクトリを絞り込む
    if opts.target and #scan_dirs > 0 then
        local target_dirs = {}
        for _, d in ipairs(scan_dirs) do
            local candidate = d .. "/" .. opts.target
            local abs = path.join(project_dir, candidate)
            if os.isdir(abs) then
                table.insert(target_dirs, candidate)
            end
        end
        if #target_dirs > 0 then
            scan_dirs = target_dirs
        end
    end

    -- scan_dirs が空ならプロジェクトルート直下をスキャン
    if #scan_dirs == 0 then
        scan_dirs = {"."}
    end

    local files = {}
    local seen = {}

    -- glob パターンを拡張子から生成
    local patterns = {}
    for _, ext in ipairs(extensions) do
        table.insert(patterns, "**" .. ext)
    end

    for _, dir in ipairs(scan_dirs) do
        local abs_dir
        if dir == "." then
            abs_dir = project_dir
        else
            abs_dir = path.join(project_dir, dir)
        end
        if os.isdir(abs_dir) then
            for _, pattern in ipairs(patterns) do
                for _, f in ipairs(os.files(path.join(abs_dir, pattern))) do
                    if not is_excluded(f) and not seen[f] then
                        table.insert(files, f)
                        seen[f] = true
                    end
                end
            end
        end
    end

    return files
end
