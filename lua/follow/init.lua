local M = {}

local defaults = {
    highlight = {
        hlgroup = "LspReferenceText",
        clear_events = { "CursorHold", "CursorHoldI" },
    },
    open = {
        exclude = {
            current_win = true,
            filetypes = {},
            buftypes = {
                "help",
                "nofile",
                "prompt",
                "quickfix",
                "terminal",
            },
            condition = nil,
        },
    },
}

local config = vim.deepcopy(defaults)

local hl = {
    augroup = vim.api.nvim_create_augroup("follow-highlight", { clear = false }),
    ns = vim.api.nvim_create_namespace("follow-highlight"),
}

function M.setup(opts)
    config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local function is_excluded_target_win(win)
    local exclude = config.open.exclude
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

local function get_candidate_target_wins(source_win)
    local wins = {}

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
        local skip_source_win = config.open.exclude.current_win and win == source_win
        if not is_float
            and not skip_source_win
            and not is_excluded_target_win(win) then
            table.insert(wins, win)
        end
    end

    table.sort(wins, function(a, b)
        return vim.api.nvim_win_get_number(a) < vim.api.nvim_win_get_number(b)
    end)

    return wins
end

-- TODO: Reuse the only eligible target window, or pick the first eligible one until
-- dismiss.nvim-style selection is wired in.
local function select_target_win(source_win)
    local wins = get_candidate_target_wins(source_win)
    if #wins > 0 then
        return wins[1]
    end

    local target_win
    vim.api.nvim_win_call(source_win, function()
        vim.cmd("split")
        target_win = vim.api.nvim_get_current_win()
    end)
    return target_win
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

-- Clear the extmark highlight and any pending clear autocmd.
local function clear_highlight()
    if hl.buf and vim.api.nvim_buf_is_valid(hl.buf) then
        vim.api.nvim_buf_clear_namespace(hl.buf, hl.ns, 0, -1)
    end
    hl.buf = nil

    if hl.clear_autocmd then
        pcall(vim.api.nvim_del_autocmd, hl.clear_autocmd)
    end
    hl.clear_autocmd = nil
end

-- Highlight the addressed line or range and register a clear autocmd
local function highlight_range(buf, start_lnum, end_lnum)
    if not location_exists(buf, start_lnum, end_lnum) then
        return
    end

    local last_lnum = end_lnum or start_lnum
    for line = start_lnum - 1, last_lnum - 1 do
        vim.api.nvim_buf_set_extmark(buf, hl.ns, line, 0, {
            line_hl_group = config.highlight.hlgroup,
        })
    end
    hl.buf = buf

    hl.clear_autocmd = vim.api.nvim_create_autocmd(config.highlight.clear_events, {
        group = hl.augroup,
        once = true,
        callback = function()
            clear_highlight()
        end,
    })
end

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

local function extract_WORD_at_cursor()
    local buf = vim.api.nvim_get_current_buf()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0)) -- row 1-based, col 0-based

    -- 1. Get current line
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if not line then return nil end

    -- 2. Find WORD start in current line
    local before = line:sub(1, col + 1)
    local word_start = before:find("%S+$")
    if not word_start then
        return nil
    end

    -- 3. Cut everything before WORD start
    local text = line:sub(word_start)

    -- 4. Append subsequent lines to reconstruct a wrapped filepath.
    -- Wrapping is assumed to end at the first whitespace.
    while not text:find("%s") do
        local next_line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
        if not next_line or next_line == "" then
            break
        end
        -- Strip leading whitespace from wrapped lines; continuation lines may
        -- be arbitrarily indented.
        text = text .. next_line:gsub("^%s+", "")
        row = row + 1
    end

    -- 5. Clamp again to a single WORD (cut everything after it)
    return text:match("^(%S+)")
end

local function resolve_file_reference(word)
    if not word then
        return nil
    end

    -- Strip punctuation around the extracted WORD
    word = word:gsub("^[%(%[%{\"'`]+", ""):gsub("[%)%]%}\"'`,;%.]+$", "")

    local path, start_lnum, end_lnum = word:match("^([%w%._%-/@~%+]+):(%d+)%-(%d+)$")
    if path and vim.fn.filereadable(path) == 1 then
        return path, tonumber(start_lnum), tonumber(end_lnum)
    end

    path, start_lnum = word:match("^([%w%._%-/@~%+]+):(%d+)$")
    if path and vim.fn.filereadable(path) == 1 then
        return path, tonumber(start_lnum)
    end

    path = word:match("^[%w%._%-/@~%+]+%.[%w]+[~]?")
    if path and vim.fn.filereadable(path) == 1 then
        return path
    end

    -- NOTE: This is a heuristic approach and has edge cases. It cannot
    -- always distinguish wrapped file paths from prose. Example:
    --   src/index.ts.
    --   Some text here ...
    -- In practice this is rare, as LLM output tends to introduce line
    -- breaks or whitespace frequently.
end

local function open_reference(path, start_lnum, end_lnum, opts)
    local source_win = vim.api.nvim_get_current_win()
    -- TODO: this must be replaced with dismiss.nvim picker
    local target_win = select_target_win(source_win)
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
        clear_highlight()
    end

    if has_location then
        ensure_location_visible(target_win, start_lnum, end_lnum)

        if opts.jump then
            vim.api.nvim_win_set_cursor(target_win, { start_lnum, 0 })
        end

        if opts.highlight then
            highlight_range(target_buf, start_lnum, end_lnum)
        end
    end

    vim.api.nvim_set_current_win(opts.jump and target_win or source_win)
end

function M.follow(opts)
    opts = vim.tbl_extend("force", {
        highlight = false,
        jump = true,
    }, opts or {})

    local word = extract_WORD_at_cursor()
    -- vim.api.nvim_echo({ { string.format("word=%s ", tostring(word)) } }, true, {})
    local path, start_lnum, end_lnum = resolve_file_reference(word)
    -- vim.api.nvim_echo({
    --     { string.format(
    --         "path=%s start=%s end=%s",
    --         tostring(path),
    --         tostring(start_lnum),
    --         tostring(end_lnum)
    --     ) },vim.fs.normalize(path)
    -- }, true, {})
    if not path then
        return false
    end

    vim.schedule(function()
        open_reference(path, start_lnum, end_lnum, opts)
    end)

    return true
end

return M
