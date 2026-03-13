local M = {}

local config = require("follow.config")
local picker = require("follow.picker")

-- Return whether this window is excluded as a target window.
--
-- Exclusion is driven entirely by the user config under `open.exclude`. A
-- window is considered excluded when its buffer filetype or buftype is listed
-- in the configured exclusion sets, or when the optional condition callback
-- returns `true` for that window. The condition callback is protected with
-- `pcall()` so a user callback failure does not break target selection;
-- callback errors are treated as "not excluded".
local function is_excluded(win)
    local exclude = config.get().open.exclude
    local buf = vim.api.nvim_win_get_buf(win)
    local condition_matches = false

    if type(exclude.condition) == "function" then
        local ok, matches = pcall(exclude.condition, win)
        condition_matches = ok and matches == true
    end

    return vim.tbl_contains(exclude.filetypes, vim.bo[buf].filetype)
        or vim.tbl_contains(exclude.buftypes, vim.bo[buf].buftype)
        or condition_matches
end

-- Collect all eligible target windows in the current tabpage.
--
-- Candidate windows are all non-floating windows in the current tabpage.
-- The source window is excluded when `open.exclude.current_win` is enabled.
-- Any window matched by the configured exclude rules is removed as well.
-- The returned list is sorted by window number so later selection and picker
-- labeling remain deterministic.
local function get_candidates(source_win)
    local wins = {}
    local open_config = config.get().open

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
        local skip_source_win = open_config.exclude.current_win and win == source_win
        if not is_float
            and not skip_source_win
            and not is_excluded(win) then
            table.insert(wins, win)
        end
    end

    table.sort(wins, function(a, b)
        return vim.api.nvim_win_get_number(a) < vim.api.nvim_win_get_number(b)
    end)

    return wins
end

-- Return the subset of candidate windows that already show the resolved target.
--
-- This lets follow detect whether one of several candidate windows is already
-- showing the file that should be opened. That information is used to avoid an
-- unnecessary picker when there is exactly one obvious destination.
local function find_wins_showing_target(wins, target_path)
    local matching_wins = {}
    local resolved_target_path = vim.fn.fnamemodify(target_path, ":p")

    for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buf_path = vim.api.nvim_buf_get_name(buf)
        if buf_path == resolved_target_path then
            table.insert(matching_wins, win)
        end
    end

    return matching_wins
end

-- Choose the window that should receive the followed reference.
--
-- The selection policy is:
--   1. If there is no eligible window, open a new one.
--   2. If there is one eligible window, use it.
--   3. If there are multiple eligible windows, exactly one already shows the
--      target file, and `open.picker.always_ask = false`, reuse that window.
--   4. Otherwise, use the picker.
function M.select_target(source_win, target_path)
    local wins = get_candidates(source_win)
    local open_config = config.get().open

    if #wins == 1 then
        return wins[1]
    end

    if #wins > 1 then
        if not open_config.picker.always_ask then
            local matching_wins = find_wins_showing_target(wins, target_path)
            if #matching_wins == 1 then
                return matching_wins[1]
            end
        end

        return picker.pick_window(wins, open_config.picker)
    end

    local target_win
    vim.api.nvim_win_call(source_win, function()
        vim.cmd("split")
        target_win = vim.api.nvim_get_current_win()
    end)
    return target_win
end

return M
