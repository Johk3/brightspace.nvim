if vim.g.loaded_brightspace then
  return
end
vim.g.loaded_brightspace = true

vim.api.nvim_create_user_command("Brightspace", function(args)
  local ok, commands = pcall(require, "brightspace.commands")
  if not ok then
    vim.notify("brightspace: commands unavailable", vim.log.levels.ERROR)
    return
  end
  commands.run(args.args)
end, {
  nargs = "?",
  complete = function()
    return { "open", "refresh", "search", "logout" }
  end,
})
