local M = {}

-- Ensure the configured picker highlight exists before the overlay is shown.
--
-- When the configured group is missing, derive it from `Visual` so the picker
-- still has a visible default appearance without requiring explicit setup.
local function derive_highlight_group(hlgroup)
    if vim.fn.hlexists(hlgroup) == 1 then
        return
    end

    local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
    visual.bold = true
    vim.api.nvim_set_hl(0, hlgroup, visual)
end

-- Assign one label character to each candidate window.
--
-- Windows are sorted by window number first so label assignment stays
-- predictable across repeated picker invocations.
local function assign_labels(windows, charset)
    local labeled_windows = {}

    table.sort(windows, function(a, b)
        return vim.api.nvim_win_get_number(a) < vim.api.nvim_win_get_number(b)
    end)

    for i, win in ipairs(windows) do
        local key = charset:sub(i, i)
        if key == "" then
            break
        end

        labeled_windows[key] = win
    end

    return labeled_windows
end

-- Render temporary overlays for all labeled windows and return their handles.
--
-- Each candidate gets a full-window mask float plus a centered label float on
-- top. The overlays are non-focusable and positioned relative to the target
-- window, so they act purely as transient picker UI.
local function show_overlays(labeled_windows, hlgroup)
    local overlays = {}

    -- Labels are shown inside temporary floats, so ensure the label highlight exists first.
    derive_highlight_group(hlgroup)

    for key, target in pairs(labeled_windows) do
        local mask_buf = vim.api.nvim_create_buf(false, true)
        local label_buf = vim.api.nvim_create_buf(false, true)
        local width = vim.api.nvim_win_get_width(target)
        local height = vim.api.nvim_win_get_height(target)
        local has_winbar = vim.api.nvim_get_option_value("winbar", { win = target }) ~= ""
        -- Windows with a winbar need the mask to be one row shorter than the
        -- window. Otherwise, it covers the bottom win separator or statusline.
        local mask_height = has_winbar and math.max(height - 1, 1) or height
        -- Both floats are positioned relative to the target window and never take focus.
        local base = {
            relative = "win",
            win = target,
            style = "minimal",
            border = "none",
            focusable = false,
            noautocmd = true,
        }
        local mask_win = vim.api.nvim_open_win(mask_buf, false, vim.tbl_extend("force", base, {
            row = 0,
            col = 0,
            width = width,
            height = mask_height,
            zindex = 100,
        }))
        vim.api.nvim_set_option_value("winhighlight", "NormalFloat:Normal", { win = mask_win })

        -- The label float provides the box styling; the buffer only needs the centered label.
        vim.api.nvim_buf_set_lines(label_buf, 0, -1, false, { "", "  " .. key, "" })

        -- A second float sits on top of the mask and provides the visible centered label.
        local label_win = vim.api.nvim_open_win(label_buf, false, vim.tbl_extend("force", base, {
            row = math.floor((height - 3) / 2),
            col = math.floor((width - 5) / 2),
            width = 5,
            height = 3,
            zindex = 200,
        }))
        vim.api.nvim_set_option_value(
            "winhighlight",
            "NormalFloat:" .. hlgroup,
            { win = label_win }
        )

        overlays[#overlays + 1] = {
            mask_win = mask_win,
            mask_buf = mask_buf,
            label_win = label_win,
            label_buf = label_buf,
        }
    end

    vim.cmd("redraw")

    return overlays
end

-- Remove all picker overlays.
--
-- Cleanup is protected because windows or buffers can disappear while input is
-- pending or while the picker is being dismissed.
local function hide_overlays(overlays)
    for _, overlay in ipairs(overlays) do
        pcall(vim.api.nvim_win_close, overlay.label_win, true)
        pcall(vim.api.nvim_buf_delete, overlay.label_buf, { force = true })
        pcall(vim.api.nvim_win_close, overlay.mask_win, true)
        pcall(vim.api.nvim_buf_delete, overlay.mask_buf, { force = true })
    end
end

-- Let the user choose one window from a provided candidate list.
--
-- The picker shows one label per candidate, waits for a single keypress, and
-- returns the chosen window. `<Esc>` and invalid input cancel the picker and
-- return `nil`.
function M.pick_window(windows, opts)
    local labeled_windows = assign_labels(vim.deepcopy(windows), opts.charset)
    local overlays = show_overlays(labeled_windows, opts.hlgroup)
    -- getchar() blocks until a single selection key or <Esc>.
    local ok, ch = pcall(vim.fn.getchar)

    hide_overlays(overlays)

    local key = ok and vim.fn.nr2char(ch)
    -- Ignore cancelled input and keys that do not map to a labeled window.
    if not key or key == vim.fn.nr2char(27) then
        return nil
    end

    return labeled_windows[key]
end

return M
