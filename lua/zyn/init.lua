local focus = require("zyn.focus")

local Zyn = {}

Zyn.options = {
    autofocus = true,
}

--- Optional setup. Safe to skip — defaults are already applied.
---@param opts table?
function Zyn.setup(opts)
    Zyn.options = vim.tbl_deep_extend("force", Zyn.options, opts or {})
end

--- Focus this nvim's pane in the host multiplexer.
--- Called by the `zyn` CLI after routing a file via `--remote-send`.
--- No-op when autofocus is off or no supported multiplexer is detected.
function Zyn.focus()
    if not Zyn.options.autofocus then
        return
    end
    focus.run()
end

--- Shell out to the `zyn` CLI to open one or more paths in the master session.
--- Accepts a string or a list of strings. Detached so it survives this nvim.
---@param paths string|string[]
function Zyn.open(paths)
    local args = type(paths) == "table" and paths or { paths }
    vim.fn.jobstart(vim.list_extend({ "zyn" }, args), { detach = true })
end

--- Toggle autofocus at runtime.
function Zyn.toggle_focus()
    Zyn.options.autofocus = not Zyn.options.autofocus
    vim.notify(
        "Zyn autofocus: " .. (Zyn.options.autofocus and "on" or "off"),
        vim.log.levels.INFO
    )
end

_G.Zyn = Zyn

return Zyn
