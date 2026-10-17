local M = {}

local function safe(value)
  return tostring(value):gsub('[^%w_-]', '_')
end

local function directory(item)
  local root = require('brightspace.config').get().notebook_dir
    or (require('brightspace.paths').data() .. '/notebooks')
  return vim.fn.expand(root) .. '/' .. safe(item.course_id) .. '/' .. safe(item.topic_id)
end

function M.find(item)
  for _, path in ipairs(vim.fn.glob(directory(item) .. '/*.ipynb', false, true)) do
    if vim.fn.filereadable(path) == 1 then return path end
  end
end

function M.matches(item, meta)
  meta = meta or {}
  local function extension(value)
    return type(value) == 'string' and value:gsub('[?#].*$', ''):lower():match('%.ipynb$')
  end
  return extension(meta.filename) or extension(item.url)
    or (meta.content_type or ''):lower():match('^application/x%-ipynb%+json')
end

-- The remote revision is deliberately absent from this path: this is user work.
function M.keep(item, source, filename)
  local existing = M.find(item)
  if existing then return existing end
  local ok, notebook = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(source), '\n'))
  end)
  if not ok or type(notebook) ~= 'table' or type(notebook.nbformat) ~= 'number'
    or type(notebook.cells) ~= 'table' or notebook.cells == vim.NIL then
    return nil, 'download is not a valid notebook'
  end
  local dir = directory(item)
  vim.fn.mkdir(dir, 'p', '0700')
  local name = (filename or item.url or item.title or 'notebook'):gsub('[?#].*$', '')
  name = name:match('([^/\\]+)$') or 'notebook'
  name = name:gsub('%.[iI][pP][yY][nN][bB]$', '')
  name = safe(name) .. '.ipynb'
  local path = dir .. '/' .. name
  local copied, err = vim.uv.fs_copyfile(source, path, 1) -- COPYFILE_EXCL: never replace user work
  if not copied then return M.find(item), err end
  vim.uv.fs_chmod(path, 384)
  return path
end

function M.open(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 then
    local windows = vim.fn.win_findbuf(buf)
    if #windows > 0 then
      vim.api.nvim_set_current_win(windows[1])
    else
      vim.cmd('tab sbuffer ' .. buf)
    end
  else
    vim.cmd('tabedit ' .. vim.fn.fnameescape(path))
  end
end

return M
