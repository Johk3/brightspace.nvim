local M = {}
local api = vim.api
local active
local namespace = api.nvim_create_namespace('brightspace.workspace')

function M.is_open()
  return active ~= nil and api.nvim_tabpage_is_valid(active.tab)
end

local function cleanup()
  local old = active
  active = nil
  if old and old.autocmd then api.nvim_del_autocmd(old.autocmd) end
  if old and old.actions.close then old.actions.close() end
end

function M.close()
  if not active then return end
  local tab = active.tab
  cleanup()
  if not api.nvim_tabpage_is_valid(tab) then return end
  if #api.nvim_list_tabpages() == 1 then vim.cmd('tabnew') end
  local current = api.nvim_get_current_tabpage()
  api.nvim_set_current_tabpage(tab)
  vim.cmd('tabclose!')
  if current ~= tab and api.nvim_tabpage_is_valid(current) then api.nvim_set_current_tabpage(current) end
end

local function current_item(pane)
  return pane.map[api.nvim_win_get_cursor(pane.win)[1]]
end

local function select_course(id)
  active.state.selected_id = id
  M.update(active.state)
  if active.actions.select_course then active.actions.select_course(id) end
end

local function expand_path(nodes, key, expanded)
  for _, node in ipairs(nodes) do
    if node.key == key then return true end
    if node.children and expand_path(node.children, key, expanded) then
      expanded[node.key] = true
      return true
    end
  end
  return false
end

local function open_item(item)
  require('brightspace.open').item(item, function()
    if not M.is_open() then return end
    require('brightspace.refresh').rebuild(active.state)
    M.update(active.state)
  end)
end

local function enter(name, toggle_only)
  if not M.is_open() then return end
  local item = current_item(active.panes[name])
  if not item then return end
  if item.module_key then
    active.state.expanded[item.module_key] = not active.state.expanded[item.module_key]
    return M.update(active.state)
  end
  if toggle_only then return end
  if name == 'courses' then return select_course(item.course_id) end
  if name == 'panel' then
    local state = active.state
    if item.course_id then select_course(item.course_id) end
    expand_path(state.trees[item.course_id] or {}, item.key, state.expanded)
    M.update(state)
    local pane = active.panes.content
    api.nvim_set_current_win(pane.win)
    for line, mapped in pairs(pane.map) do
      if mapped.key == item.key then api.nvim_win_set_cursor(pane.win, {line, 0}); break end
    end
  end
  open_item(item)
end

local function mark(name, all)
  if not M.is_open() then return end
  local state = active.state
  local store = require('brightspace.store')
  if all then
    if state.selected_id then store.mark_all_seen(require('brightspace.refresh').items(state, state.selected_id)) end
  else
    local item = current_item(active.panes[name])
    if item and item.key then store.mark_seen(item) end
  end
  require('brightspace.refresh').rebuild(state)
  M.update(state)
end

local function configure(name, win)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(win, buf)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'brightspace'
  vim.bo[buf].modifiable = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].wrap = false
  vim.wo[win].winfixwidth = name ~= 'content'
  vim.wo[win].winfixbuf = true
  local pane = {win = win, buf = buf, map = {}}
  active.panes[name] = pane
  local function map(key, callback, mode) vim.keymap.set(mode or 'n', key, callback, {buffer = buf, silent = true}) end
  map('<CR>', function() enter(name) end)
  for _, key in ipairs({'o', 'za'}) do map(key, function() enter(name, true) end) end
  map('q', M.close)
  map('R', function() if active.actions.refresh then active.actions.refresh() end end)
  local function search() if active.actions.search then active.actions.search() end end
  map('/', search)
  map('<leader>/', search, {'n', 'x'})
  map('Q', function() active.state.show_all = not active.state.show_all; M.update(active.state) end)
  map('m', function() mark(name, false) end)
  map('M', function() mark(name, true) end)
end

local function draw(pane, lines, map, highlights)
  if not api.nvim_buf_is_valid(pane.buf) or not api.nvim_win_is_valid(pane.win) then return end
  local cursor = api.nvim_win_get_cursor(pane.win)
  local previous = pane.map[cursor[1]]
  vim.bo[pane.buf].modifiable = true
  api.nvim_buf_set_lines(pane.buf, 0, -1, false, lines)
  vim.bo[pane.buf].modifiable = false
  pane.map = map
  api.nvim_buf_clear_namespace(pane.buf, namespace, 0, -1)
  for _, highlight in ipairs(highlights) do
    api.nvim_buf_set_extmark(pane.buf, namespace, highlight.line - 1, 0,
      {line_hl_group = highlight.group})
  end
  local line = math.min(cursor[1], #lines)
  if previous then
    for candidate, item in pairs(map) do
      if (previous.key and item.key == previous.key)
        or (previous.module_key and item.module_key == previous.module_key)
        or (previous.course_id and not previous.key and item.course_id == previous.course_id) then
        line = candidate
        break
      end
    end
  end
  api.nvim_win_set_cursor(pane.win, {math.max(1, line), 0})
end

function M.update(state)
  if not M.is_open() then return end
  active.state = state
  local render = require('brightspace.ui.render')
  local selected
  for _, course in ipairs(state.courses) do if course.id == state.selected_id then selected = course end end
  draw(active.panes.courses, render.courses(state.groups, {
    selected_id = state.selected_id, show_all = state.show_all, new_counts = state.new_counts,
  }))
  draw(active.panes.content, render.content(selected, state.trees[state.selected_id] or {},
    state.news[state.selected_id] or {}, state.info[state.selected_id], state.expanded))
  draw(active.panes.panel, render.panel(state.deadlines, state.new_items, os.time()))
end

function M.open(state, actions)
  if M.is_open() then
    api.nvim_set_current_tabpage(active.tab)
    if actions then active.actions = actions end
    M.update(state)
    return
  end
  require('brightspace.ui.highlights').setup()
  vim.cmd('tabnew')
  active = {tab = api.nvim_get_current_tabpage(), panes = {}, state = state, actions = actions or {}}
  local left = api.nvim_get_current_win()
  vim.cmd('rightbelow vsplit')
  local middle = api.nvim_get_current_win()
  vim.cmd('rightbelow vsplit')
  local right = api.nvim_get_current_win()
  configure('courses', left)
  configure('content', middle)
  configure('panel', right)
  api.nvim_win_set_width(left, 30)
  api.nvim_win_set_width(right, 42)
  api.nvim_set_current_win(left)
  active.autocmd = api.nvim_create_autocmd('TabClosed', {callback = function()
    if active and not api.nvim_tabpage_is_valid(active.tab) then cleanup() end
  end})
  M.update(state)
end

return M
