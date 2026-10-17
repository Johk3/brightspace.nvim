-- Optional lazy.nvim specification. See README.md for Python environment setup.
local env = vim.fn.stdpath('data') .. '/notebook-venv/bin/'

local function notebook_cell(direction)
  if not vim.api.nvim_buf_get_name(0):match('%.ipynb$') then return end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cells, active = {}, nil
  for line, text in ipairs(lines) do
    if not active and text:match('^%s*```python%s*$') then
      active = line
    elseif active and text:match('^%s*```%s*$') then
      cells[#cells + 1] = { first = active, last = line - 1 }
      active = nil
    end
  end
  if direction == 'run' then
    for _, cell in ipairs(cells) do
      if row >= cell.first and row <= cell.last then
        if cell.last >= cell.first + 1 then
          local last = lines[cell.last] or ''
          vim.fn.MoltenEvaluateRange(cell.first + 1, cell.last, 1, #last + 1)
        end
        return
      end
    end
    vim.notify('Place the cursor inside a Python code cell to run it.', vim.log.levels.INFO)
  elseif direction == 'next' then
    for _, cell in ipairs(cells) do
      if cell.first > row then vim.api.nvim_win_set_cursor(0, { cell.first, 0 }); return end
    end
  else
    for i = #cells, 1, -1 do
      if cells[i].first < row then vim.api.nvim_win_set_cursor(0, { cells[i].first, 0 }); return end
    end
  end
end

local notebook_attachments = {}

local function extract_notebook_attachments(buf)
  local notebook = vim.api.nvim_buf_get_name(buf)
  if not notebook:match('%.ipynb$') then return end
  local root = vim.fn.stdpath('cache') .. '/brightspace/notebook-images/' .. vim.fn.sha256(notebook)
  vim.fn.mkdir(root, 'p', 448)
  local script = [[
import base64, json, pathlib, sys
source, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
notebook = json.loads(source.read_text())
paths = {}
root.mkdir(parents=True, exist_ok=True, mode=0o700)
for cell in notebook.get("cells", []):
    for name, bundles in cell.get("attachments", {}).items():
        for mime, data in bundles.items():
            if mime.startswith("image/"):
                target = root / pathlib.Path(name).name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(base64.b64decode("".join(data) if isinstance(data, list) else data))
                target.chmod(0o600)
                paths["attachment:" + name] = str(target)
                break
print(json.dumps(paths))
]]
  local result = vim.system({ env .. 'python', '-c', script, notebook, root }, { text = true }):wait()
  if result.code ~= 0 then
    vim.notify('Could not extract notebook image attachments: ' .. result.stderr, vim.log.levels.WARN)
    return
  end
  notebook_attachments[notebook] = vim.json.decode(result.stdout)
end

local function run_cell(advance)
  notebook_cell('run')
  if advance then vim.schedule(function() notebook_cell('next') end) end
end

return {
  {
    'goerz/jupytext.nvim',
    lazy = false, -- register BufReadCmd before the first notebook opens
    opts = {
      jupytext = env .. 'jupytext',
      format = 'md',
      filetype = 'markdown',
      update = true, -- preserve existing outputs and metadata on save
      async_write = false, -- finish conversion before Molten exports outputs
    },
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = 'markdown',
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons', '3rd/image.nvim' },
    opts = {
      file_types = { 'markdown' },
      latex = { converter = { env .. 'latex2text' } },
    },
    keys = {
      { '<leader>nr', function() run_cell(false) end, desc = 'Notebook: run cell' },
      { '<leader>nn', function() run_cell(true) end, desc = 'Notebook: run and advance' },
      { ']h', function() notebook_cell('next') end, desc = 'Next cell' },
      { '[h', function() notebook_cell('prev') end, desc = 'Previous cell' },
    },
  },
  {
    'benlubas/molten-nvim',
    lazy = false,
    dependencies = { '3rd/image.nvim' },
    build = ':UpdateRemotePlugins',
    init = function()
      vim.g.python3_host_prog = env .. 'python'
      vim.g.molten_image_provider = 'image.nvim'
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
    '3rd/image.nvim',
    build = false,
    opts = {
      backend = 'kitty',
      processor = 'magick_cli',
      max_width = 100,
      max_height = 12,
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', '' },
      integrations = {
        markdown = {
          download_remote_images = false,
          resolve_image_path = function(document_path, image_path, fallback)
            local path = notebook_attachments[document_path]
              and notebook_attachments[document_path][image_path]
            return path or fallback(document_path, image_path)
          end,
        },
      },
    },
    init = function()
      local group = vim.api.nvim_create_augroup('BrightspaceNotebookAttachments', { clear = true })
      vim.api.nvim_create_autocmd('FileType', {
        group = group,
        pattern = 'markdown',
        callback = function(args)
          if vim.api.nvim_buf_get_name(args.buf):match('%.ipynb$') then
            extract_notebook_attachments(args.buf)
          end
        end,
      })
    end,
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
