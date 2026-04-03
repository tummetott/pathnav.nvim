local M = {}

if vim.fn.has("nvim-0.9.0") == 0 then
    vim.notify("pathnav.nvim requires Neovim 0.9.0 or newer", vim.log.levels.ERROR)
    return M
end

local config = require("pathnav.config")
local parser = require("pathnav.parser")
local target = require("pathnav.target")
local highlight = require("pathnav.highlight")
-- TODO: maybe piggyback on the match block of dismiss.nvim
-- TODO: add vimdoc

---@class pathnav.OpenOptions
---@field highlight? boolean
---@field jump? boolean
---@field target_window? pathnav.ConfigOptions.TargetWindow

-- Apply user config for the plugin.
---@param opts? pathnav.ConfigOptions
function M.setup(opts)
    config.setup(opts)
end

-- Return whether the addressed line or line-range exists in the buffer.
local function location_exists(buf, start_lnum, end_lnum)
    if not start_lnum then
        return false
    end

    local line_count = vim.api.nvim_buf_line_count(buf)
    if line_count == 0 then
        return false
    end

    if start_lnum < 1 or start_lnum > line_count then
        return false
    end

    if end_lnum and (end_lnum < 1 or end_lnum > line_count) then
        return false
    end

    return true
end

-- Adjust the target window viewport to show the addressed location.
--
-- If the line or range is already on screen, leave the view unchanged.
-- Otherwise move the cursor to the start line and place it roughly one quarter
-- of the window height below the top.
local function adjust_viewport(win, start_lnum, end_lnum)
    local last_lnum = end_lnum or start_lnum
    local first_visible
    local last_visible
    vim.api.nvim_win_call(win, function()
        first_visible = vim.fn.line("w0")
        last_visible = vim.fn.line("w$")
    end)

    if start_lnum >= first_visible and last_lnum <= last_visible then
        return
    end

    vim.api.nvim_win_call(win, function()
        vim.api.nvim_win_set_cursor(0, { start_lnum, 0 })
        local view = vim.fn.winsaveview()
        view.topline = math.max(start_lnum - math.floor(vim.api.nvim_win_get_height(0) * 0.25), 1)
        vim.fn.winrestview(view)
    end)
end

-- Open the resolved file in a target window.
--
-- This chooses the target window and opens the file there when necessary.
local function open_file(source_win, path, target_win_opts)
    local target_win = target.select_target(source_win, path, target_win_opts)
    if not target_win then
        return nil
    end

    local target_buf = vim.api.nvim_win_get_buf(target_win)
    local target_path = vim.api.nvim_buf_get_name(target_buf)
    if target_path ~= vim.fn.fnamemodify(path, ":p") then
        vim.api.nvim_win_call(target_win, function()
            vim.cmd("edit " .. vim.fn.fnameescape(path))
        end)
        target_buf = vim.api.nvim_win_get_buf(target_win)
    end

    return target_win, target_buf
end

-- Open the path under the cursor.
--
-- Returns `false` when no readable path could be resolved at the cursor.
-- Returns `true` once a path was resolved, even if target selection is later
-- cancelled by the user.
---@param opts? pathnav.OpenOptions
---@return boolean
function M.open(opts)
    local source_win = vim.api.nvim_get_current_win()

    opts = vim.tbl_extend("force", {
        highlight = true,
        jump = true,
    }, opts or {})

    if opts.highlight then
        highlight.clear()
    end

    local path, start_lnum, end_lnum = parser.parse_path_under_cursor()
    if not path then
        return false
    end

    local target_win, target_buf = open_file(source_win, path, opts.target_window)
    if not target_win then
        return true
    end

    local has_location = location_exists(target_buf, start_lnum, end_lnum)
    if has_location then
        adjust_viewport(target_win, start_lnum, end_lnum)

        if opts.jump then
            vim.api.nvim_win_set_cursor(target_win, { start_lnum, 0 })
        end

        if opts.highlight then
            highlight.range(target_buf, start_lnum, end_lnum)
        end
    end

    vim.api.nvim_set_current_win(opts.jump and target_win or source_win)
    return true
end

return M
