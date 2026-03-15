local M = {}

local function current_checkout_commit(state)
    if state.current_commit == nil then
        state.current_commit = vim.fn.systemlist({ "git", "rev-parse", "HEAD" })[1] or false
        if vim.v.shell_error ~= 0 then
            state.current_commit = false
        end
    end

    return state.current_commit
end

local function resolve_hashtag_reference(token, state)
    -- Split the token into a path part and a final `#L...` line suffix.
    -- The suffix match is limited to the characters used by supported line
    -- fragments so unrelated trailing text is less likely to be mistaken for
    -- a file reference.
    local path, line_fragment = token:match("^(.-)(#L[%dCL%-]+)$")
    if not path or not line_fragment then
        return nil
    end

    -- Detect blob permalinks in the path portion. When present, only accept
    -- them if the embedded commit matches the current checkout.
    -- TODO: warn when commit is present but not checked out
    local _, commit, blob_path = path:match("^(.-)/blob/([^/]+)/(.+)$")
    if commit then
        if current_checkout_commit(state) ~= commit then
            return nil
        end
        path = blob_path
    end

    -- Parse the leading line number from `#L<start>...`.
    local start_lnum, suffix = line_fragment:match("^#L(%d+)(.*)$")
    if not start_lnum then
        return nil
    end

    start_lnum = tonumber(start_lnum)
    -- Ignore optional column information after the start line.
    suffix = suffix:gsub("^C%d+", "")

    local end_lnum
    if suffix ~= "" then
        -- Parse an optional range end from either `-<end>` or `-L<end>`.
        end_lnum = suffix:match("^%-(%d+)")
        if not end_lnum then
            end_lnum = suffix:match("^%-L(%d+)")
        end
        if not end_lnum then
            return nil
        end
        end_lnum = tonumber(end_lnum)
    end

    -- Only succeed once the resolved path exists locally.
    if path ~= "" and vim.fn.filereadable(path) == 1 then
        return path, start_lnum, end_lnum
    end
end

local function resolve_colon_reference(token)
    -- Split off the final `:<line>...` suffix. The suffix is restricted to the
    -- characters used by supported colon references so unrelated trailing
    -- punctuation is less likely to be mistaken for line information.
    local path, line_suffix = token:match("^(.-)(:%d[%d:%-]*)$")
    if not path or not line_suffix then
        return nil
    end

    -- Parse the starting line from `:<start>...`.
    local start_lnum, suffix = line_suffix:match("^:(%d+)(.*)$")
    if not start_lnum then
        return nil
    end

    start_lnum = tonumber(start_lnum)

    -- Ignore optional column information after the start line.
    suffix = suffix:gsub("^:%d+", "")

    local end_lnum
    if suffix ~= "" then
        -- Parse an optional range end from `-<end>` and ignore its optional
        -- trailing column.
        end_lnum, suffix = suffix:match("^%-(%d+)(.*)$")
        if not end_lnum then
            return nil
        end

        suffix = suffix:gsub("^:%d+", "")
        if suffix ~= "" then
            return nil
        end

        end_lnum = tonumber(end_lnum)
    end

    if path ~= "" and vim.fn.filereadable(path) == 1 then
        return path, start_lnum, end_lnum
    end
end

-- Resolve one extracted candidate into a local file reference.
local function resolve_reference(token, state)
    if not token then
        return nil
    end

    -- If the token contains markdown link syntax, resolve the destination from
    -- its trailing `](...)` section.
    local reference = token:match(".*](%b())")
    if reference then
        token = reference:sub(2, -2)
        token = token:match("^<(.*)>$") or token
    end

    -- Strip punctuation from the outer edges so references embedded in prose
    -- like `(foo.lua:12).` can still be recognized.
    token = token:gsub("^[%(%[%{\"'`]+", ""):gsub("[%)%]%}\"'`,;%.]+$", "")

    local path, start_lnum, end_lnum = resolve_hashtag_reference(token, state)
    if path then
        return path, start_lnum, end_lnum
    end

    path, start_lnum, end_lnum = resolve_colon_reference(token)
    if path then
        return path, start_lnum, end_lnum
    end

    if token ~= "" and vim.fn.filereadable(token) == 1 then
        return token
    end
end

-- Parse the file reference under the cursor.
--
-- This scans one logical token under the cursor, tries resolving it after the
-- first line, then progressively appends up to four continuation lines.
function M.parse_cursor_reference()
    local buf = vim.api.nvim_get_current_buf()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0)) -- row 1-based, col 0-based
    local state = {}

    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    if not line then
        return nil
    end

    local before = line:sub(1, col + 1)
    local WORD_start = before:find("%S+$")
    if not WORD_start then
        return nil
    end

    local token = line:sub(WORD_start)
    for consumed_lines = 1, 5 do
        local whitespace_start = token:find("%s")
        local candidate = whitespace_start and token:sub(1, whitespace_start - 1) or token
        local path, start_lnum, end_lnum = resolve_reference(candidate, state)
        if path then
            return path, start_lnum, end_lnum
        end

        if whitespace_start then
            return nil
        end

        if consumed_lines == 5 then
            return nil
        end

        local next_line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
        if not next_line then
            return nil
        end

        local continuation = next_line:gsub("^%s+", "")
        if continuation == "" then
            return nil
        end

        token = token .. continuation
        row = row + 1
    end
end

return M
