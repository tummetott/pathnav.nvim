local M = {}

---@alias pathnav.SplitDirection
---| "left"
---| "right"
---| "above"
---| "below"

---@class pathnav.Config.Highlight
---@field hlgroup string
---@field clear_events string[]

---@class pathnav.ConfigOptions.Highlight
---@field hlgroup? string
---@field clear_events? string[]

---@class pathnav.Config.TargetWindow.Exclude
---@field current boolean
---@field filetypes string[]
---@field buftypes string[]
---@field condition? fun(win: integer): boolean

---@class pathnav.ConfigOptions.TargetWindow.Exclude
---@field current? boolean
---@field filetypes? string[]
---@field buftypes? string[]
---@field condition? fun(win: integer): boolean

---@class pathnav.Config.TargetWindow.Prefer
---@field matching_file boolean
---@field last_target boolean

---@class pathnav.ConfigOptions.TargetWindow.Prefer
---@field matching_file? boolean
---@field last_target? boolean

---@class pathnav.Config.TargetWindow.Split
---@field direction pathnav.SplitDirection
---@field force boolean

---@class pathnav.ConfigOptions.TargetWindow.Split
---@field direction? pathnav.SplitDirection
---@field force? boolean

---@class pathnav.Config.TargetWindow
---@field exclude pathnav.Config.TargetWindow.Exclude
---@field prefer pathnav.Config.TargetWindow.Prefer
---@field split pathnav.Config.TargetWindow.Split

---@class pathnav.ConfigOptions.TargetWindow
---@field exclude? pathnav.ConfigOptions.TargetWindow.Exclude
---@field prefer? pathnav.ConfigOptions.TargetWindow.Prefer
---@field split? pathnav.ConfigOptions.TargetWindow.Split

---@class pathnav.Config.Picker
---@field charset string
---@field hlgroup string

---@class pathnav.ConfigOptions.Picker
---@field charset? string
---@field hlgroup? string

---@class pathnav.Config
---@field highlight pathnav.Config.Highlight
---@field target_window pathnav.Config.TargetWindow
---@field picker pathnav.Config.Picker

---@class pathnav.ConfigOptions
---@field highlight? pathnav.ConfigOptions.Highlight
---@field target_window? pathnav.ConfigOptions.TargetWindow
---@field picker? pathnav.ConfigOptions.Picker

-- Default plugin configuration.
---@type pathnav.Config
local defaults = {
    highlight = {
        hlgroup = "PathnavReferenceText",
        clear_events = { "CursorMoved" },
    },
    target_window = {
        exclude = {
            current = true,
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
        prefer = {
            matching_file = true,
            last_target = false,
        },
        split = {
            direction = vim.o.splitright and "right" or "left",
            force = false,
        },
    },
    picker = {
        charset = "jklasdfhguiopqwert",
        hlgroup = "PathnavPickerLabel",
    },
}

-- Active plugin configuration.
--
-- This starts as a deepcopy of the defaults and is replaced with the merged
-- user config whenever `setup()` is called.
---@type pathnav.Config
local config = vim.deepcopy(defaults)

-- Merge user options into the defaults and replace the active config.
---@param opts? pathnav.ConfigOptions
function M.setup(opts)
    config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

-- Return the current active config.
---@return pathnav.Config
function M.get()
    return config
end

return M
