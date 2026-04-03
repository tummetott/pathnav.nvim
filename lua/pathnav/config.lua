local M = {}

-- Default plugin configuration.
--
-- These values define the runtime behavior when the user does not override
-- them in `setup()`.
local defaults = {
    highlight = {
        hlgroup = "LspReferenceText",
        clear_events = { "CursorHold", "CursorHoldI" },
    },
    target = {
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
        picker = {
            always_ask = false,
            charset = "jklasdfhguiopqwert",
            hlgroup = "PathnavPickerLabel",
        },
    },
}

-- Active plugin configuration.
--
-- This starts as a deepcopy of the defaults and is replaced with the merged
-- user config whenever `setup()` is called.
local config = vim.deepcopy(defaults)

-- Merge user options into the defaults and replace the active config.
function M.setup(opts)
    config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

-- Return the current active config.
function M.get()
    return config
end

return M
