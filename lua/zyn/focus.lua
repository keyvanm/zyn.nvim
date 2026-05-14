local M = {}

-- ============================================================================
-- Multiplexer pane focus (zellij / tmux)
-- ============================================================================

local function mux_focus_cmd()
    local zellij_pane = os.getenv("ZELLIJ_PANE_ID")
    if zellij_pane then
        return { "zellij", "action", "focus-pane-with-id", zellij_pane }
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

    return walk_up_until(function(pid) return pid_to_addr[pid] end)
end

-- ============================================================================
-- Sway window focus
-- ============================================================================

local sway_pid = nil

-- Recursively collect all PIDs that own a window in the sway tree.
local function collect_sway_pids(node, set)
    if type(node) ~= "table" then return end
    if node.pid then set[node.pid] = true end
    for _, n in ipairs(node.nodes or {}) do collect_sway_pids(n, set) end
    for _, n in ipairs(node.floating_nodes or {}) do collect_sway_pids(n, set) end
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
    collect_sway_pids(tree, pids)

    return walk_up_until(function(pid)
        if pids[pid] then return pid end
        return nil
    end)
end

-- ============================================================================
-- Public
-- ============================================================================

function M.run()
    if hyprland_address then
        vim.fn.jobstart({
            "hyprctl",
            "dispatch",
            "focuswindow",
            "address:" .. hyprland_address,
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
