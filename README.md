# pathnav.nvim

`pathnav.nvim` detects paths under the cursor and **opens**, **highlights**,
or **jumps** to the referenced location. It is especially useful for
LLM-generated output, where paths are embedded in prose.

The plugin understands multiple path formats, such as:

* Absolute / relative paths
* Markdown embedded paths
* `path:line` locations
* `path:line-line` ranges
* GitHub-style `#L` line fragments
* GitHub blob permalinks
* Paths wrapped in surrounding prose or punctuation

It is also **git-aware** and warns you if you try to open a path that does not match your current checked-out commit.

## 🚀 API

```lua
---@param opts? pathnav.ConfigOptions
require("pathnav").setup(opts)
```

Initializes and configures the plugin. See [Configuration](#configuration).

```lua
---@param opts? pathnav.OpenOptions
---@return boolean
require("pathnav").open(opts)
```

Opens the path under the cursor. Returns `false` if no readable path could be
resolved; `true` otherwise (including when the user cancels window selection).

| Option | Type | Default | Description |
|---|---|---|---|
| `jump` | `boolean` | `true` | Move the cursor to the referenced location and switch focus to the target window. |
| `highlight` | `boolean` | `true` | Highlight the referenced line or range. |
| `target_window` | `pathnav.ConfigOptions.TargetWindow` | — | Override target window selection for this call. Same shape as the `target_window` section in `setup()`. |

## ⚡️ Requirements

Neovim `0.9.0` or newer

## 📦 Installation with `lazy.nvim`

```lua
{
    "tummetott/pathnav.nvim",
    lazy = true,
    ---@type pathnav.ConfigOptions
    opts = {
        -- Optional config overrides
    },
    keys = {
        {
            "<c-]>",
            function()
                if not require("pathnav").open() then
                    vim.api.nvim_feedkeys(vim.keycode('<C-]>'), 'n', false)
                end
            end,
            desc = "Open path or fallback to tag jump",
        },
        -- CAUTION: `<c-[>` only works in terminal emulators that support the
        -- kitty keyboard protocol. Otherwise, it overrides `<Esc>`
        {
            "<c-[>",
            function()
                require("pathnav").open({
                    jump = false,
                    highlight = true,
                })
            end,
            desc = "Highlight path location",
        },
    },
}
```

## Configuration

```lua
---@type pathnav.ConfigOptions
{
    -- Highlight options for referenced lines.
    highlight = {
        -- Highlight group used for the referenced line or range.
        hlgroup = "PathnavReferenceText",
        -- Events that clear the active reference highlight.
        clear_events = { "CursorMoved" },
    },

    -- Target window selection options.
    target_window = {
        -- Exclude windows from target selection.
        exclude = {
            -- Exclude the current window.
            current = true,
            -- Exclude buffers with these filetypes.
            filetypes = {},
            -- Exclude buffers with these buftypes.
            buftypes = {
                "help",
                "nofile",
                "prompt",
                "quickfix",
                "terminal",
            },
            -- Callback that receives a window id and returns `true` when that
            -- window is excluded from target selection.
            condition = nil,
        },
        -- Prefer candidate windows that match these conditions.
        prefer = {
            -- Prefer a window that already shows the referenced file.
            matching_file = true,
            -- Prefer the window selected by the previous pathnav jump.
            last_target = false,
        },
        -- Split behavior when a new target window is created.
        split = {
            -- Direction in which the new split opens.
            direction = vim.o.splitright and "right" or "left",
            -- Always open in a new split instead of reusing candidates.
            force = false,
        },
    },

    -- Window picker appearance.
    picker = {
        -- Characters used as picker labels.
        charset = "jklasdfhguiopqwert",
        -- Highlight group used for picker labels.
        hlgroup = "PathnavPickerLabel",
    }
}
```

## 🪟 Window selection

When opening a path, `pathnav.nvim` selects a target window from the current tabpage.

Floating windows are ignored. The remaining windows are filtered by
`target_window.exclude`.

Selection rules:

1. If `target_window.split.force` is enabled or there is no candidate window, open a new split.
2. If there is one candidate window, use it.
3. If the configured preferences identify one preferred candidate window, use it.
4. Otherwise, use the picker.

Picker controls:

* press the displayed label to select a window
* `<Esc>` or invalid input cancels the operation

## 🐛 Caveats

`require("pathnav").open()` cannot be used from within an `expr` mapping.

`open()` changes windows, opens buffers, moves the cursor, and adds highlights.
These operations are not allowed while an `expr` mapping is being evaluated.
Deferring the call would fix this, but introduces other edge cases with highlight
clearing.

Use `vim.api.nvim_feedkeys(vim.keycode('<key>'), <mode>, false)` to fall back to
the original key behavior instead.


❤️ Tummetott
