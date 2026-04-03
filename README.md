# pathnav.nvim

Navigate paths in text.

`pathnav.nvim` detects paths under the cursor and opens the addressed location. It is designed for paths embedded in prose, such as LLM-generated reports, documentation, logs, or markdown.

The plugin understands multiple path formats and can optionally **jump to** or **highlight** the addressed lines.

It is also **git-aware** and supports GitHub-style permalinks.

---

# Features

* Open paths under the cursor
* Jump to a specific line or range
* Highlight addressed lines without moving the cursor
* Detect paths inside plain text or markdown
* Understand GitHub-style permalinks
* Resolve permalinks against the current git checkout
* Smart window selection with optional picker

---

# Installation

Example using **lazy.nvim**:

```lua
return {
    "tummetott/pathnav.nvim",
    lazy = true,
    opts = {
        -- See config section
    },
    keys = {
        {
            "<c-]>",
            function()
                if not require("pathnav").open({
                    jump = true,
                    highlight = false,
                }) then
                    vim.cmd("normal! <C-]>")
                end
            end,
            desc = "Open path or fallback to tag jump",
        },
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

---

# Usage

The main entry point is:

```lua
require("pathnav").open()
```

Options:

| Option      | Description                                |
| ----------- | ------------------------------------------ |
| `jump`      | Move the cursor to the addressed location |
| `highlight` | Highlight the addressed line or range     |

Example: highlight the addressed location without changing the current window focus.

```lua
require("pathnav").open({
    jump = false,
    highlight = true,
})
```

The highlight is cleared automatically when one of the configured `clear_events` fires.

---

# Window selection

When opening a path, `pathnav.nvim` selects a target window from the **current tabpage**.

Floating windows and excluded buffers are ignored.

Selection rules:

1. **No eligible window** → open a new split
2. **One eligible window** → reuse it
3. **Multiple eligible windows**

   * reuse the one already showing the target file if possible
   * otherwise show a window picker

Picker controls:

* press the displayed label to select a window
* `<Esc>` or invalid input cancels the operation

---

# Configuration

Default configuration:

```lua
{
    highlight = {
        hlgroup = "LspReferenceText",
        clear_events = { "CursorHold", "CursorHoldI" },
    },

    target = {
        -- Target windows are selected from the current tabpage after applying
        -- these exclusion rules.
        exclude = {
            current_win = true,
            filetypes = {},
            buftypes = { "help", "nofile", "prompt", "quickfix", "terminal" },
            condition = nil,
        },

        picker = {
            always_ask = false,
            charset = "jklasdfhguiopqwert",
            hlgroup = "PathnavPickerLabel",
        },
    },
}
```

# Supported path formats

`pathnav.nvim` detects the following patterns:

``` 
path/to/file.lua
~/path/to/file.lua
path/to/file.lua:12
path/to/file.lua:12-20
path/to/file.lua#L12
path/to/file.lua#L12-20
path/to/file.lua#L12-L20
[link](path/to/file.lua#L12)
.../blob/<commit>/path/to/file.lua#L12
```

These may appear in plain text, markdown, or GitHub links.
