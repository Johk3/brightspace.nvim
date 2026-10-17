if vim.g.loaded_brightspace then
  return
end
vim.g.loaded_brightspace = true

vim.api.nvim_create_user_command("Brightspace", function(args)
  require("brightspace.commands").run(args.args)
end, {
  nargs = "?",
  complete = function()
    return { "open", "refresh", "search", "logout" }
  end,
})
