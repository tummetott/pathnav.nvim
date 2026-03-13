local M = {}
local config = require("follow.config")
local parser = require("follow.parser")
local target = require("follow.target")
local highlight = require("follow.highlight")
-- TODO: support github syle ranges
-- TODO: fix bug with wrapped lines
-- TODO: find better plugin name

-- Apply user config for the plugin.
function M.setup(opts)
    config.setup(opts)
end

-- Return whether the addressed line or line-range exists in the buffer
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
-- Otherwise move the cursor to the start line and center the window around it.
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

    vim.api.nvim_win_set_cursor(win, { start_lnum, 0 })
    vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zz")
    end)
end

-- Open the resolved reference in a target window and apply the requested view behavior.
--
-- This chooses the target window, opens the file there when necessary, moves to
-- the addressed location when it exists, and optionally highlights that
-- location instead of leaving focus in the target window.
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

    if opts.highlight then
        highlight.clear()
    end

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
-- cursor. When a reference is found, the actual window and buffer changes are
-- scheduled so this function can be used safely from expression mappings.
function M.follow(opts)
    opts = vim.tbl_extend("force", {
        highlight = false,
        jump = true,
    }, opts or {})

    local path, start_lnum, end_lnum = parser.parse_cursor_reference()
    if not path then
        return false
    end

    vim.schedule(function()
        open_reference(path, start_lnum, end_lnum, opts)
    end)

    return true
end

return M
