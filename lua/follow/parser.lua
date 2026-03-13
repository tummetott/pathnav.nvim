local M = {}

-- Extract the WORD under the cursor, including wrapped path continuations.
--
-- This is tailored to LLM-style output where a file reference may be broken
-- across multiple visual lines with indentation on continuation lines. The
-- result is still just one WORD, so parsing can happen separately afterward.
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

-- Resolve one extracted WORD into a readable file reference.
--
-- Supported forms are:
--   - `path:start-end`
--   - `path:start`
--   - `path`
--
-- Surrounding punctuation is stripped first so references embedded in prose or
-- markdown can still be recognized.
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

-- Parse the file reference under the cursor.
--
-- This combines cursor extraction and reference resolution, returning the
-- resolved path plus optional line or line-range information.
function M.parse_cursor_reference()
    local word = extract_WORD_at_cursor()
    return resolve_file_reference(word)
end

return M
