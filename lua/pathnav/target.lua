local M = {}

local config = require("pathnav.config")
local picker = require("pathnav.picker")
local last_target_win

-- Return whether this tabpage is excluded as a target tabpage.
--
-- Exclusion is driven entirely by the `target_tabpage.exclude` callback, which
-- is protected with `pcall()` so a user callback failure does not break target
-- selection; callback errors are treated as "not excluded".
local function is_tabpage_excluded(tabpage, tabpage_config)
    if type(tabpage_config.exclude) ~= "function" then
        return false
    end

    local ok, matches = pcall(tabpage_config.exclude, tabpage)
    return ok and matches == true
end

local function notify_error(message)
    vim.notify("pathnav.nvim: " .. message, vim.log.levels.ERROR)
end

local BROKEN_ORDER = "`target_tabpage.order` must return a list of tabpage handles"

-- Collect the tabpages that may host the target window, in search order.
--
-- The order comes from `target_tabpage.order`, which is free to return any
-- tabpages in any order. Duplicates and stale handles are dropped, so a
-- tabpage closed between jumps is skipped rather than reported, and
-- `target_tabpage.exclude` removes the tabpages that must never receive a
-- file.
local function get_search_tabpages(tabpage_config)
    local ok, order = pcall(tabpage_config.order)
    if not ok or type(order) ~= "table" then
        notify_error(BROKEN_ORDER)
        return nil
    end

    local tabpages = {}
    local seen = {}
    local searched = 0

    for _, tabpage in ipairs(order) do
        if type(tabpage) ~= "number" then
            notify_error(BROKEN_ORDER)
            return nil
        end

        if vim.api.nvim_tabpage_is_valid(tabpage) and not seen[tabpage] then
            seen[tabpage] = true
            searched = searched + 1
            if not is_tabpage_excluded(tabpage, tabpage_config) then
                table.insert(tabpages, tabpage)
            end
        end
    end

    if searched == 0 then
        notify_error("`target_tabpage.order` returned no open tabpage")
        return nil
    end

    if #tabpages == 0 then
        notify_error("`target_tabpage.exclude` rejected every searched tabpage")
        return nil
    end

    return tabpages
end

-- Return whether this window is excluded as a target window.
--
-- Exclusion is driven entirely by the user config under `target_window.exclude`. A
-- window is considered excluded when its buffer filetype or buftype is listed
-- in the configured exclusion sets, or when the optional condition callback
-- returns `true` for that window. The condition callback is protected with
-- `pcall()` so a user callback failure does not break target selection;
-- callback errors are treated as "not excluded".
local function is_excluded(win, source_win, window_config)
    local exclude = window_config.exclude
    local buf = vim.api.nvim_win_get_buf(win)

    if exclude.current and win == source_win then
        return true
    end

    if type(exclude.condition) == "function" then
        local ok, matches = pcall(exclude.condition, win)
        if ok and matches == true then
            return true
        end
    end

    return vim.tbl_contains(exclude.filetypes, vim.bo[buf].filetype)
        or vim.tbl_contains(exclude.buftypes, vim.bo[buf].buftype)
end

-- Collect all eligible target windows in one tabpage.
--
-- Candidate windows are all non-floating windows in that tabpage that are not
-- excluded by `target_window.exclude`. The returned list is sorted by window
-- number so later selection and picker labeling remain deterministic.
local function get_tabpage_candidates(tabpage, source_win, window_config)
    local wins = {}

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
        if not is_float
            and not is_excluded(win, source_win, window_config) then
            table.insert(wins, win)
        end
    end

    table.sort(wins, function(a, b)
        return vim.api.nvim_win_get_number(a) < vim.api.nvim_win_get_number(b)
    end)

    return wins
end

-- Return the candidate windows of the first searched tabpage that offers any.
local function get_candidates(tabpages, source_win, window_config)
    for _, tabpage in ipairs(tabpages) do
        local wins = get_tabpage_candidates(tabpage, source_win, window_config)
        if #wins > 0 then
            return wins
        end
    end

    return {}
end

-- Return the subset of candidate windows that already show the resolved file.
--
-- This lets pathnav detect whether one of several candidate windows is already
-- showing the file that should be opened.
local function get_wins_showing_file(wins, file_path)
    local matching_wins = {}
    local resolved_file_path = vim.fn.fnamemodify(file_path, ":p")

    for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buf_path = vim.api.nvim_buf_get_name(buf)
        if buf_path == resolved_file_path then
            table.insert(matching_wins, win)
        end
    end

    return matching_wins
end

-- Return one preferred window from the candidate list.
--
-- This returns a window only when `target_window.prefer` resolves the choice to
-- one candidate. When the configured preferences leave multiple candidates
-- equally valid, it returns `nil`.
local function get_preferred_window(wins, file_path, window_config)
    local prefer = window_config.prefer

    if prefer.matching_file then
        local matching_wins = get_wins_showing_file(wins, file_path)
        if #matching_wins == 1 then
            return matching_wins[1]
        end
        if #matching_wins > 1 then
            wins = matching_wins
        end
    end

    if prefer.last_target and last_target_win and vim.api.nvim_win_is_valid(last_target_win) then
        for _, win in ipairs(wins) do
            if win == last_target_win then
                return win
            end
        end
    end
end

-- Open one split in a tabpage using the configured placement.
--
-- The split is placed relative to that tabpage's current window, which is the
-- window it had focused when it was last left.
local function open_split(tabpage, window_config)
    local split = window_config.split
    local commands = {
        left = "leftabove vsplit",
        right = "rightbelow vsplit",
        above = "leftabove split",
        below = "rightbelow split",
    }

    local target_win
    vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tabpage), function()
        vim.cmd(commands[split.direction] or commands.right)
        target_win = vim.api.nvim_get_current_win()
    end)
    return target_win
end

-- Let the user pick one of the candidate windows.
--
-- Picker labels are floats anchored to the candidate windows, so they only
-- render in the tabpage holding them. That tabpage is entered first to make
-- them visible, and left again when the picker is cancelled, since nothing
-- opens in that case.
local function run_picker(wins)
    local origin = vim.api.nvim_get_current_tabpage()
    local tabpage = vim.api.nvim_win_get_tabpage(wins[1])
    if tabpage == origin then
        return picker.pick_window(wins)
    end

    vim.api.nvim_set_current_tabpage(tabpage)
    local target_win = picker.pick_window(wins)
    if not target_win then
        vim.api.nvim_set_current_tabpage(origin)
    end

    return target_win
end

-- Choose the window in which the file will be opened.
-- Candidates come from the first searched tabpage that offers any.
-- Within that scope the selection policy is:
--
-- 1. If `target_window.split.force` is enabled or there is no candidate window, open a new split.
-- 2. If there is one candidate window, use it.
-- 3. If the configured preferences identify one preferred candidate window, use it.
-- 4. Otherwise, use the picker.
--
-- Returns `nil` when the picker is cancelled, and when the tabpage search
-- yields nothing, which leaves nowhere for the file to go and is reported to
-- the user.
---@param source_win integer
---@param file_path string
---@param window_config? pathnav.ConfigOptions.TargetWindow
---@param tabpage_config? pathnav.ConfigOptions.TargetTabpage
---@return integer?
function M.select_target(source_win, file_path, window_config, tabpage_config)
    window_config = vim.tbl_deep_extend(
        "force",
        vim.deepcopy(config.get().target_window),
        window_config or {}
    )
    tabpage_config = vim.tbl_deep_extend(
        "force",
        vim.deepcopy(config.get().target_tabpage),
        tabpage_config or {}
    )

    local tabpages = get_search_tabpages(tabpage_config)
    if not tabpages then
        return nil
    end

    local wins = get_candidates(tabpages, source_win, window_config)
    local target_win

    if window_config.split.force or #wins == 0 then
        target_win = open_split(tabpages[1], window_config)
    elseif #wins == 1 then
        target_win = wins[1]
    else
        target_win = get_preferred_window(wins, file_path, window_config)
            or run_picker(wins)
    end

    if target_win then
        last_target_win = target_win
    end

    return target_win
end

return M
