if _G.ZynLoaded then
    return
end
_G.ZynLoaded = true

require("zyn")

vim.api.nvim_create_user_command("ZynToggleFocus", function()
    require("zyn").toggle_focus()
end, { desc = "Toggle Zyn autofocus on remote file open" })
