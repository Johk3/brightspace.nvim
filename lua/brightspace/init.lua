local M = {}

---@param opts table|nil
function M.setup(opts)
  local config = require("brightspace.config")
  config.setup(opts)
  local key = config.get().keymap
  if key then
    vim.keymap.set("n", key, "<Cmd>Brightspace open<CR>", { desc = "Brightspace" })
  end
end

return M
