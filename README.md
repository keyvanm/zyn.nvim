# zyn.nvim

Editor-side companion for the [`zyn`](https://github.com/keyvanm/zyn) CLI.

When `zyn` routes a file into a running nvim session, it appends a `:lua Zyn.focus()` call to the `--remote-send` payload. This plugin defines that function so nvim's pane gets focused in your terminal multiplexer — without it, the file opens but you stay in the pane that called `zyn`.

The `zyn` CLI guards the call with `type(Zyn) == 'table'`, so users without this plugin aren't broken — they just don't get focus.

## Installation

```lua
vim.pack.add({ "https://github.com/keyvanm/giga.nvim" })
```

No `setup()` required — defaults are applied on load.

## Behaviour

`Zyn.focus()` runs two layers of focus, both async via `vim.fn.jobstart`:

**1. Window-manager focus** (Hyprland / Sway)

| Detected env var               | Action                                                        |
| ------------------------------ | ------------------------------------------------------------- |
| `$HYPRLAND_INSTANCE_SIGNATURE` | `hyprctl dispatch focuswindow address:<terminal-window-addr>` |
| `$SWAYSOCK`                    | `swaymsg [pid=<terminal-pid>] focus`                          |

The terminal's window is resolved once at plugin load: walk up nvim's process tree, match each PID against the WM's known windows (`hyprctl clients -j` or `swaymsg -t get_tree`), take the first hit. Cached for the life of the session — both WMs' focus calls switch workspace and focus the window in one shot, so moving the terminal across workspaces later still works without re-detection.

**2. Multiplexer pane focus** (zellij / tmux)

| Detected env var  | Action                                             |
| ----------------- | -------------------------------------------------- |
| `$ZELLIJ_PANE_ID` | `zellij action focus-pane-with-id $ZELLIJ_PANE_ID` |
| `$TMUX_PANE`      | `tmux select-pane -t $TMUX_PANE`                   |

If neither layer detects anything, `Zyn.focus()` is a silent no-op.

## Configuration

```lua
require("zyn").setup({
    autofocus = true,  -- default
})
```

Toggle at runtime with `:ZynToggleFocus` or `:lua Zyn.toggle_focus()`.

The CLI also has its own opt-out — `zyn --no-focus <file>` or `ZYN_NO_FOCUS=1` — which omits the `Zyn.focus()` call from the payload entirely. Use that for one-off invocations; use `:ZynToggleFocus` to silence focus from inside the editor.

## API

```lua
require("zyn").focus()         -- focus the pane (no-op if disabled)
require("zyn").toggle_focus()  -- flip autofocus
require("zyn").setup(opts)     -- override defaults
```

---

Boilerplate provided by [🔌 Neovim plugin boilerplate](https://github.com/shortcuts/neovim-plugin-boilerplate)
