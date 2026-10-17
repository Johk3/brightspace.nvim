local M = {}

local defaults = {
  base_url = "https://brightspace.tudelft.nl",
  viewer = "xdg-open", -- string or list of command parts
  notebook_dir = false, -- defaults to stdpath("data")/brightspace/notebooks
  keymap = "<leader>bs", -- false disables the mapping
  cache_ttl = 300, -- seconds
  keepalive = 600, -- seconds
  deadline_days = 30,
}

local current = vim.deepcopy(defaults)

---@param opts table|nil
function M.setup(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@return table
function M.get()
  return current
end

return M
