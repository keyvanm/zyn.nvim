local M = {}

-- ============================================================================
-- Multiplexer pane focus (zellij / tmux)
-- ============================================================================

local function mux_focus_cmd()
    local zellij_pane = os.getenv("ZELLIJ_PANE_ID")
    if zellij_pane then
        return { "zellij", "action", "focus-pane-id", zellij_pane }
    end

    local tmux_pane = os.getenv("TMUX_PANE")
    if tmux_pane then
        return { "tmux", "select-pane", "-t", tmux_pane }
    end

    return nil
end

-- ============================================================================
-- Process tree walk
-- ============================================================================

-- Parse parent PID from /proc/PID/stat. The `comm` field can contain spaces
-- and parens, so we anchor on the LAST `)` and parse from there — standard
-- procfs trick.
local function get_ppid(pid)
    local f = io.open("/proc/" .. pid .. "/stat", "r")
    if not f then return nil end
    local stat = f:read("*a")
    f:close()
    local up_to_last_paren = stat:match(".*%)")
    if not up_to_last_paren then return nil end
    local rest = stat:sub(#up_to_last_paren + 1)
    local _, ppid = rest:match("^%s*(%S+)%s+(%d+)")
    return tonumber(ppid)
end

-- Walk up nvim's process tree, applying `predicate(pid)`. Returns the first
-- non-nil value the predicate produces, or nil after `max_depth` hops.
local function walk_up_until(predicate, max_depth)
    max_depth = max_depth or 10
    local pid = vim.fn.getpid()
    for _ = 1, max_depth do
        local result = predicate(pid)
        if result then return result end
        local ppid = get_ppid(pid)
        if not ppid or ppid == pid or ppid <= 1 then return nil end
        pid = ppid
    end
    return nil
end

-- ============================================================================
-- Hyprland window focus
-- ============================================================================

-- Cached at plugin load. `dispatch focuswindow address:X` brings the window's
-- workspace into focus and focuses the window in one shot, so subsequent moves
-- of the terminal across workspaces don't invalidate this address.
local hyprland_address = nil

local function hyprland_active_address()
    local out = vim.fn.system({ "hyprctl", "activewindow", "-j" })
    if vim.v.shell_error ~= 0 then return nil end
    local ok, win = pcall(vim.json.decode, out)
    if not ok or type(win) ~= "table" then return nil end
    return win.address
end

local function detect_hyprland_address()
    if not os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
        return nil
    end

    local out = vim.fn.system({ "hyprctl", "clients", "-j" })
    if vim.v.shell_error ~= 0 then return nil end
    local ok, clients = pcall(vim.json.decode, out)
    if not ok or type(clients) ~= "table" then return nil end

    local pid_to_addr = {}
    for _, c in ipairs(clients) do
        if c.pid and c.address then
            pid_to_addr[c.pid] = c.address
        end
    end

    -- Proc-walk fails when an intermediate process is daemonized and reparented
    -- to init (notably zellij-server) — the terminal's PID is no longer an
    -- ancestor of nvim. Fall back to the active window, which at plugin-load
    -- time is the terminal that just spawned nvim.
    return walk_up_until(function(pid) return pid_to_addr[pid] end)
        or hyprland_active_address()
end

-- ============================================================================
-- Sway window focus
-- ============================================================================

local sway_pid = nil

-- Recursively collect all window PIDs in the sway tree, and remember which
-- one is currently focused (used as a fallback when proc-walk fails).
local function scan_sway_tree(node, set, focused)
    if type(node) ~= "table" then return focused end
    if node.pid then
        set[node.pid] = true
        if node.focused then focused = node.pid end
    end
    for _, n in ipairs(node.nodes or {}) do
        focused = scan_sway_tree(n, set, focused)
    end
    for _, n in ipairs(node.floating_nodes or {}) do
        focused = scan_sway_tree(n, set, focused)
    end
    return focused
end

local function detect_sway_pid()
    if not os.getenv("SWAYSOCK") then
        return nil
    end

    local out = vim.fn.system({ "swaymsg", "-t", "get_tree" })
    if vim.v.shell_error ~= 0 then return nil end
    local ok, tree = pcall(vim.json.decode, out)
    if not ok then return nil end

    local pids = {}
    local focused_pid = scan_sway_tree(tree, pids, nil)

    -- See the Hyprland fallback note: daemonized multiplexer servers hide the
    -- terminal from nvim's ancestry. The focused window at plugin-load time is
    -- the terminal that just spawned nvim.
    return walk_up_until(function(pid)
        if pids[pid] then return pid end
        return nil
    end) or focused_pid
end

-- ============================================================================
-- Public
-- ============================================================================

function M.run()
    if hyprland_address then
        -- Hyprland >= 0.55 routes `hyprctl dispatch` args through a Lua eval
        -- wrapped in `return hl.dispatch(<args>)`. The old `focuswindow
        -- address:X` form is no longer parseable; the dispatch arg must be a
        -- single Lua expression evaluating to a dispatcher.
        vim.fn.jobstart({
            "hyprctl",
            "dispatch",
            'hl.dsp.focus({ window = "address:' .. hyprland_address .. '" })',
        })
    elseif sway_pid then
        vim.fn.jobstart({
            "swaymsg",
            "[pid=" .. sway_pid .. "]",
            "focus",
        })
    end

    local cmd = mux_focus_cmd()
    if cmd then
        vim.fn.jobstart(cmd)
    end
end

-- One-time detection at load. Cheap and only runs in the long-lived nvim that
-- becomes the session.
hyprland_address = detect_hyprland_address()
sway_pid = detect_sway_pid()

return M
