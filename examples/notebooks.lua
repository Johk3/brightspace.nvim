-- Optional lazy.nvim specification. See README.md for Python environment setup.
local env = vim.fn.stdpath('data') .. '/notebook-venv/bin/'

local function run_cell(advance)
  local navigator = require('notebook-navigator')
  local cell = navigator.miniai_spec('i')
  if cell.to.line < cell.from.line then return end
  local marker = cell.from.line > 1
    and vim.api.nvim_buf_get_lines(0, cell.from.line - 2, cell.from.line - 1, false)[1] or ''
  if marker:find('[markdown]', 1, true) or marker:find('[raw]', 1, true)
    or (cell.from.line == 1 and vim.api.nvim_buf_get_name(0):match('%.ipynb$')) then
    if advance then navigator.move_cell('d') end
    return
  end
  local last = vim.api.nvim_buf_get_lines(0, cell.to.line - 1, cell.to.line, false)[1] or ''
  -- Use exact columns: the standard adapter includes the next cell marker,
  -- which can prevent Molten from matching saved notebook cells on export.
  vim.fn.MoltenEvaluateRange(cell.from.line, cell.to.line, 1, #last + 1)
  if advance then navigator.move_cell('d') end
end

return {
  {
    'goerz/jupytext.nvim',
    lazy = false, -- register BufReadCmd before the first notebook opens
    opts = {
      jupytext = env .. 'jupytext',
      format = 'py:percent',
      filetype = 'python',
      update = true, -- preserve existing outputs and metadata on save
      async_write = false, -- finish conversion before Molten exports outputs
    },
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
    'GCBallesteros/NotebookNavigator.nvim',
    ft = 'python',
    opts = { repl_provider = 'molten', syntax_highlight = true },
    keys = {
      { ']h', function() require('notebook-navigator').move_cell('d') end, desc = 'Next cell' },
      { '[h', function() require('notebook-navigator').move_cell('u') end, desc = 'Previous cell' },
      { '<leader>nr', function() run_cell(false) end, desc = 'Notebook: run cell' },
      { '<leader>nn', function() run_cell(true) end, desc = 'Notebook: run and advance' },
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
