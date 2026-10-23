describe('workspace lifecycle', function()
  local workspace, state, original, closes
  before_each(function()
    workspace = require('brightspace.ui.workspace')
    original = vim.api.nvim_get_current_tabpage()
    state = require('brightspace.state').new()
    state.courses = {{id=1, code='TEST1001', name='Example', current=true, quarter_key='2026Q1', quarter_label='2026/27 Q1'}}
    state.groups = {{label='Current', courses=state.courses}}
    state.selected_id = 1
    closes = 0
  end)
  after_each(function() workspace.close() end)
  it('opens three reusable panes and closes without exiting', function()
    workspace.open(state, {close=function() closes=closes+1 end})
    local tab = vim.api.nvim_get_current_tabpage()
    local wins = vim.api.nvim_tabpage_list_wins(tab)
    assert.equals(3, #wins)
    local buffers = {}
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      buffers[#buffers+1] = buf
      assert.equals('nofile', vim.bo[buf].buftype)
      assert.equals('wipe', vim.bo[buf].bufhidden)
      assert.is_false(vim.bo[buf].modifiable)
    end
    workspace.update(state)
    workspace.open(state)
    assert.equals(tab, vim.api.nvim_get_current_tabpage())
    for i, win in ipairs(wins) do assert.equals(buffers[i], vim.api.nvim_win_get_buf(win)) end
    workspace.close()
    assert.equals(original, vim.api.nvim_get_current_tabpage())
    assert.equals(1, closes)
    assert.is_false(workspace.is_open())
  end)
  it('cleans up when its tab is closed externally', function()
    workspace.open(state, {close=function() closes=closes+1 end})
    vim.cmd('tabclose')
    vim.wait(100, function() return closes==1 end)
    assert.equals(1, closes)
    assert.is_false(workspace.is_open())
  end)
  it('can close when its workspace is the only tab', function()
    workspace.open(state, {close=function() closes=closes+1 end})
    vim.api.nvim_set_current_tabpage(original)
    vim.cmd('tabclose')
    workspace.close()
    assert.equals(1, #vim.api.nvim_list_tabpages())
    assert.equals(1, closes)
    assert.is_false(workspace.is_open())
  end)
  it('selects courses, expands panel paths and opens their items', function()
    local item = {key='topic:1:2', kind='topic', course_id=1, title='Slides'}
    state.trees[1] = {{key='module:1:1', kind='module', title='Week', children={item}}}
    state.new_items = {item}
    local selected, opened
    local opener = require('brightspace.open')
    local old_open = opener.item
    opener.item = function(value) opened=value end
    workspace.open(state, {select_course=function(id) selected=id end})
    local wins = vim.api.nvim_tabpage_list_wins(0)
    local left, middle, right = wins[1], wins[2], wins[3]
    local function press(win, needle, key)
      vim.api.nvim_set_current_win(win)
      local buf = vim.api.nvim_win_get_buf(win)
      for line, text in ipairs(vim.api.nvim_buf_get_lines(buf,0,-1,false)) do
        if text:find(needle,1,true) then vim.api.nvim_win_set_cursor(win,{line,0}); break end
      end
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf,'n')) do
        if mapping.lhs==key then mapping.callback(); return end
      end
      error('Missing mapping '..key)
    end
    local ok, err = pcall(function()
      press(left, 'TEST1001', '<CR>')
      assert.equals(1, selected)
      press(right, 'Slides', '<CR>')
      assert.equals(item, opened)
      assert.is_true(state.expanded['module:1:1'])
      assert.equals(middle, vim.api.nvim_get_current_win())
      local line = vim.api.nvim_win_get_cursor(middle)[1]
      assert.is_truthy(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(middle),line-1,line,false)[1]:find('Slides'))
      press(middle, 'Week', 'o')
      assert.is_false(state.expanded['module:1:1'])
    end)
    opener.item = old_open
    assert.is_true(ok, err)
  end)
  it('routes refresh and search and marks the selected course seen', function()
    local item = {key='news:1:2', kind='news', course_id=1, title='Example announcement'}
    state.news[1] = {item}
    local refreshes, searches, marked, all = 0, 0
    local store = require('brightspace.store')
    local old_seen, old_all = store.mark_seen, store.mark_all_seen
    store.mark_seen = function(value) marked=value end
    store.mark_all_seen = function(values) all=values end
    workspace.open(state, {refresh=function() refreshes=refreshes+1 end,
      search=function() searches=searches+1 end})
    local middle = vim.api.nvim_tabpage_list_wins(0)[2]
    local buf = vim.api.nvim_win_get_buf(middle)
    vim.api.nvim_set_current_win(middle)
    local function press(key)
      for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf,'n')) do
        if mapping.lhs==key then return mapping.callback() end
      end
      error('Missing mapping '..key)
    end
    local ok, err = pcall(function()
      for line,text in ipairs(vim.api.nvim_buf_get_lines(buf,0,-1,false)) do
        if text:find(item.title,1,true) then vim.api.nvim_win_set_cursor(middle,{line,0}) end
      end
      press('m')
      assert.equals(item, marked)
      press('M')
      assert.equals(item, all[1])
      press('R'); press('/')
      assert.equals(1, refreshes)
      assert.equals(1, searches)
      vim.fn.maparg('<leader>/', 'n', false, true).callback()
      assert.equals(2, searches)
      vim.fn.maparg('<leader>/', 'x', false, true).callback()
      assert.equals(3, searches)
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do assert.is_true(vim.wo[win].winfixbuf) end
      press('Q')
      assert.is_true(state.show_all)
    end)
    store.mark_seen, store.mark_all_seen = old_seen, old_all
    assert.is_true(ok, err)
  end)
end)
