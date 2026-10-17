-- Optional lazy.nvim specification. See README.md for Python environment setup.
local env = vim.fn.stdpath('data') .. '/notebook-venv/bin/'

local function run_cell(advance)
  require('quarto.runner').run_cell()
  if advance then vim.schedule(function() vim.fn.search('^```{', 'W') end) end
end

local function move_cell(direction)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  if direction == 'next' then
    for line = row + 1, #lines do
      if lines[line]:match('^```%b{}') then vim.api.nvim_win_set_cursor(0, { line, 0 }); return end
    end
  else
    for line = row - 1, 1, -1 do
      if lines[line]:match('^```%b{}') then vim.api.nvim_win_set_cursor(0, { line, 0 }); return end
    end
  end
end

return {
  {
    'goerz/jupytext.nvim',
    lazy = false, -- register BufReadCmd before the first notebook opens
    opts = {
      jupytext = env .. 'jupytext',
      format = 'qmd',
      filetype = 'quarto',
      update = true, -- preserve existing outputs and metadata on save
      async_write = false, -- finish conversion before Molten exports outputs
    },
  },
  {
    'quarto-dev/quarto-nvim',
    ft = 'quarto',
    dependencies = { 'jmbuhr/otter.nvim', 'nvim-treesitter/nvim-treesitter' },
    keys = {
      { '<leader>nr', function() run_cell(false) end, desc = 'Notebook: run cell' },
      { '<leader>nn', function() run_cell(true) end, desc = 'Notebook: run and advance' },
      { ']h', function() move_cell('next') end, desc = 'Next cell' },
      { '[h', function() move_cell('prev') end, desc = 'Previous cell' },
    },
    opts = {
      codeRunner = { enabled = true, default_method = 'molten' },
      lspFeatures = {
        enabled = true,
        languages = { 'python' },
        completion = { enabled = false },
        diagnostics = { enabled = false },
      },
    },
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown', 'quarto' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    opts = { file_types = { 'markdown', 'quarto' } },
  },
  {
    'benlubas/molten-nvim',
    lazy = false,
    build = ':UpdateRemotePlugins',
    init = function()
      vim.g.python3_host_prog = env .. 'python'
      vim.g.molten_image_provider = 'none'
      vim.g.molten_virt_text_output = true
      vim.g.molten_auto_open_output = false
    end,
    config = function()
      -- Some distributions disable the built-in remote plugin loader.
      vim.cmd('runtime plugin/rplugin.vim')
      local function highlights()
        vim.api.nvim_set_hl(0, 'MoltenCell', { link = 'Visual' })
        vim.api.nvim_set_hl(0, 'MoltenVirtualText', { link = 'DiagnosticInfo' })
        vim.api.nvim_set_hl(0, 'MoltenOutputBorderSuccess', { link = 'DiagnosticOk' })
        vim.api.nvim_set_hl(0, 'MoltenOutputBorderFail', { link = 'DiagnosticError' })
      end
      highlights()
      local colors = vim.api.nvim_create_augroup('BrightspaceNotebookHighlights', { clear = true })
      vim.api.nvim_create_autocmd('ColorScheme', { group = colors, callback = highlights })
      local group = vim.api.nvim_create_augroup('NotebookOutputs', { clear = true })
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = group,
        pattern = '*.ipynb',
        callback = function()
          if vim.fn.exists(':MoltenExportOutput') == 2
            and #vim.fn.MoltenRunningKernels(true) == 1 then
            vim.cmd('MoltenExportOutput!')
            vim.b.mtime = vim.uv.fs_stat(vim.api.nvim_buf_get_name(0)).mtime
          end
        end,
      })
    end,
    keys = {
      { '<leader>ni', '<cmd>MoltenInit<cr>', desc = 'Notebook: choose kernel' },
      { '<leader>no', '<cmd>MoltenShowOutput<cr>', desc = 'Notebook: show output' },
      { '<leader>nl', '<cmd>MoltenImportOutput<cr>', desc = 'Notebook: load saved outputs' },
      { '<leader>nx', '<cmd>MoltenInterrupt<cr>', desc = 'Notebook: interrupt' },
      { '<leader>nq', '<cmd>MoltenDeinit<cr>', desc = 'Notebook: stop kernel' },
      { '<leader>np', '<cmd>MoltenImagePopup<cr>', desc = 'Notebook: open plot' },
    },
  },
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
  },
  {
    'lewis6991/gitsigns.nvim',
    opts = function(_, opts)
      local attach = opts.on_attach
      opts.on_attach = function(buf)
        -- The buffer contains Python, while Git sees notebook JSON.
        if vim.api.nvim_buf_get_name(buf):match('%.ipynb$') then return false end
        if attach then return attach(buf) end
      end
    end,
  },
}
