# follow.nvim

Navigate file references in text.

`follow.nvim` detects file references under the cursor and opens the referenced location. It is designed for references embedded in prose, such as LLM-generated reports, documentation, logs, or markdown.

The plugin understands multiple reference formats and can optionally **jump to** or **highlight** the referenced lines.

It is also **git-aware** and supports GitHub-style permalinks.

---

# Features

* Open file references under the cursor
* Jump to a specific line or range
* Highlight referenced lines without moving the cursor
* Detect references inside plain text or markdown
* Understand GitHub-style permalinks
* Resolve permalinks against the current git checkout
* Smart window selection with optional picker

---

# Installation

Example using **lazy.nvim**:

```lua
return {
  "tummetott/follow.nvim",
  lazy = true,
  opts = {
    -- See config section
  },
  keys = {
    {
      "<c-]>",
      function()
        if not require("follow").follow({
          jump = true,
          highlight = false,
        }) then
          return "<C-]>"
        end
      end,
      expr = true,
      desc = "Follow reference or fallback to tag jump",
    },
    {
      "<c-[>",
      function()
        local ok = require("follow").follow({
          jump = false,
          highlight = true,
        })
      desc = "Highlight reference",
    },
  },
}
```

---

# Usage

The main entry point is:

```lua
require("follow").follow()
```

Options:

| Option      | Description                                |
| ----------- | ------------------------------------------ |
| `jump`      | Move the cursor to the referenced location |
| `highlight` | Highlight the referenced line or range     |

Example: highlight the referenced location without changing the current window focus.

```lua
require("follow").follow({
  jump = false,
  highlight = true,
})
```

The highlight is cleared automatically when one of the configured `clear_events` fires.

---

# Window selection

When opening a reference, `follow.nvim` selects a target window from the **current tabpage**.

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

  open = {
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
      hlgroup = "FollowPickerLabel",
    },
  },
}
```

# Supported reference formats

`follow.nvim` detects the following patterns:

```
path/to/file.lua
path/to/file.lua:12
path/to/file.lua:12-20
path/to/file.lua#L12
path/to/file.lua#L12-20
path/to/file.lua#L12-L20
.../blob/<commit>/path/to/file.lua#L12
.../blob/<commit>/path/to/file.lua#L12-20
.../blob/<commit>/path/to/file.lua#L12-L20
```

These may appear in plain text, markdown, or GitHub links.

---
