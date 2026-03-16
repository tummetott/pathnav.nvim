local M = {}
local config = require("follow.config")
local parser = require("follow.parser")
local target = require("follow.target")
local highlight = require("follow.highlight")
-- TODO: find better plugin name
-- TODO: maybe piggyback on the match block of dismiss.nvim
-- TODO: rename follow()
-- TODO: new keymap for open in new split, even if eledible windows exist? introduce follow({ force_split = true }) ?

-- Apply user config for the plugin.
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

-- Ensure the addressed location is visible in the target window.
--
-- If the line or range is already on screen, leave the view unchanged.
-- Otherwise move the cursor to the start line and place it roughly one quarter
-- of the window height below the top.
local function ensure_location_visible(win, start_lnum, end_lnum)
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

-- Open the resolved reference in a target window and apply the requested view behavior.
--
-- This chooses the target window, opens the file there when necessary, moves to
-- the addressed location when it exists, and optionally highlights that
-- location while leaving focus in the source window.
local function open_reference(path, start_lnum, end_lnum, opts)
    local source_win = vim.api.nvim_get_current_win()
    local target_win = target.select_target(source_win, path)
    if not target_win then
        return
    end

    local target_buf = vim.api.nvim_win_get_buf(target_win)
    local target_path = vim.api.nvim_buf_get_name(target_buf)
    if target_path ~= vim.fn.fnamemodify(path, ":p") then
        vim.api.nvim_win_call(target_win, function()
            vim.cmd("edit " .. vim.fn.fnameescape(path))
        end)
        target_buf = vim.api.nvim_win_get_buf(target_win)
    end
    local has_location = location_exists(target_buf, start_lnum, end_lnum)

    if has_location then
        ensure_location_visible(target_win, start_lnum, end_lnum)

        if opts.jump then
            vim.api.nvim_win_set_cursor(target_win, { start_lnum, 0 })
        end

        if opts.highlight then
            highlight.range(target_buf, start_lnum, end_lnum)
        end
    end

    vim.api.nvim_set_current_win(opts.jump and target_win or source_win)
end

-- Follow the file reference under the cursor.
--
-- Returns `false` when no readable file reference could be resolved at the
-- cursor.
function M.follow(opts)
    opts = vim.tbl_extend("force", {
        highlight = false,
        jump = true,
    }, opts or {})

    if opts.highlight then
        highlight.clear()
    end

    local path, start_lnum, end_lnum = parser.parse_cursor_reference()
    if not path then
        return false
    end

    open_reference(path, start_lnum, end_lnum, opts)
    return true
end

return M
