local M = {}
function M.setup()
  local links = {
    BrightspaceUrgent = 'DiagnosticError',
    BrightspaceSoon = 'DiagnosticWarn',
    BrightspaceDim = 'Comment',
    BrightspaceNew = 'DiagnosticInfo',
    BrightspaceHeader = 'Title',
  }
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, {link = target, default = true})
  end
end
return M
