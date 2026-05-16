# zyn.nvim

Editor-side companion for the [`zyn`](https://github.com/keyvanm/zyn) CLI. Install this and the nvim that receives a routed file also *gets focused* — across multiplexer panes, Hyprland windows, and sway workspaces. Without it, the file opens but you stay in the pane that called `zyn`.

When `zyn` routes a file into a running nvim session, it appends a `:lua Zyn.focus()` call to the `--remote-send` payload. This plugin defines that function. The CLI guards the call with `type(Zyn) == 'table'`, so users without the plugin aren't broken — they just don't get auto-focus.

## Installation

```lua
vim.pack.add({ "https://github.com/keyvanm/zyn.nvim" })
```

No `setup()` required — defaults are applied on load.

## Behaviour

`Zyn.focus()` runs two layers, both async via `vim.fn.jobstart`. If neither layer detects anything, it's a silent no-op.

**1. Window-manager focus** (Hyprland / sway)

| Detected env var               | Action                                                                    |
| ------------------------------ | ------------------------------------------------------------------------- |
| `$HYPRLAND_INSTANCE_SIGNATURE` | `hyprctl dispatch 'hl.dsp.focus({ window = "address:<terminal-addr>" })'` |
| `$SWAYSOCK`                    | `swaymsg [pid=<terminal-pid>] focus`                                      |

**2. Multiplexer pane focus** (zellij / tmux)

| Detected env var  | Action                                        |
| ----------------- | --------------------------------------------- |
| `$ZELLIJ_PANE_ID` | `zellij action focus-pane-id $ZELLIJ_PANE_ID` |
| `$TMUX_PANE`      | `tmux select-pane -t $TMUX_PANE`              |

### How the terminal window is resolved (Hyprland / sway)

At plugin-load time, walk up nvim's process tree and match each PID against the WM's known windows (`hyprctl clients -j` or `swaymsg -t get_tree`). Take the first hit. Cached for the life of the session.

If the walk finds no match — typically because a multiplexer server (e.g. `zellij-server`) is daemonized and reparented to init, hiding the terminal from nvim's ancestry — fall back to the currently active/focused window, which at plugin-load is the terminal that just spawned nvim. Both WMs' focus calls switch workspace and focus the window in one shot, so moving the terminal across workspaces later still works without re-detection.

The Hyprland command uses the Lua-config dispatcher form introduced in 0.55; the legacy `focuswindow address:X` syntax no longer parses.

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
