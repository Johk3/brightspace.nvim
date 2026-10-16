local M = {}

local function dir(env, std)
  local p = vim.env[env]
  if p == nil or p == "" then
    p = vim.fn.stdpath(std) .. "/brightspace"
  end
  vim.fn.mkdir(p, "p", "0700")
  return p
end

function M.state()
  return dir("BRIGHTSPACE_STATE_DIR", "state")
end

function M.cache()
  return dir("BRIGHTSPACE_CACHE_DIR", "cache")
end

function M.data()
  return dir("BRIGHTSPACE_DATA_DIR", "data")
end

function M.cookie_jar()
  return M.state() .. "/cookies.txt"
end

return M
