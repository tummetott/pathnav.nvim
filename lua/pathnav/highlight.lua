local M = {}

local config = require("pathnav.config")

local hl = {
    augroup = vim.api.nvim_create_augroup("pathnav-highlight", { clear = false }),
    ns = vim.api.nvim_create_namespace("pathnav-highlight"),
}

-- Clear the extmark highlight and any pending clear autocmd.
function M.clear()
    if hl.buf and vim.api.nvim_buf_is_valid(hl.buf) then
        vim.api.nvim_buf_clear_namespace(hl.buf, hl.ns, 0, -1)
    end
    hl.buf = nil

    if hl.clear_autocmd then
        pcall(vim.api.nvim_del_autocmd, hl.clear_autocmd)
    end
    hl.clear_autocmd = nil
end

-- Highlight the addressed line or range and register a clear autocmd.
function M.range(buf, start_lnum, end_lnum)
    local last_lnum = end_lnum or start_lnum

    local highlight = config.get().highlight
    if vim.fn.hlexists(highlight.hlgroup) ~= 1 then
        vim.api.nvim_set_hl(0, highlight.hlgroup, { link = "LspReferenceText" })
    end

    for line = start_lnum - 1, last_lnum - 1 do
        vim.api.nvim_buf_set_extmark(buf, hl.ns, line, 0, {
            line_hl_group = highlight.hlgroup,
        })
    end
    hl.buf = buf

    -- Register the clear autocmd on the next scheduler tick so the initial
    -- cursor movement does not clear the highlight immediately.
    vim.schedule(function()
        if hl.buf ~= buf or not vim.api.nvim_buf_is_valid(buf) then
            return
        end

        hl.clear_autocmd = vim.api.nvim_create_autocmd(highlight.clear_events, {
            group = hl.augroup,
            once = true,
            callback = function()
                M.clear()
            end,
        })
    end)
end

return M
