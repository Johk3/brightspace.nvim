vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(os.getenv("PLENARY_DIR") or (vim.fn.stdpath("data") .. "/lazy/plenary.nvim"))
vim.cmd("runtime plugin/plenary.vim")
