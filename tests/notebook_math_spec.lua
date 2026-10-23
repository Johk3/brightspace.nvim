describe('notebook display math', function()
  local math = require('brightspace.notebook_math')

  it('wraps bare display environments for Markdown rendering', function()
    local input = {
      'Explanation:',
      '\\begin{cases}',
      'x = 1 \\\\',
      'y = 2',
      '\\end{cases}',
    }
    local actual, changed = math.normalize(input)
    assert.is_true(changed)
    assert.same({
      'Explanation:', '$$', '\\begin{cases}', 'x = 1 \\\\', 'y = 2', '\\end{cases}', '$$',
    }, actual)
  end)

  it('leaves delimited math and fenced examples alone', function()
    local input = {
      '$$', '\\begin{cases}', '\\end{cases}', '$$',
      '```latex', '\\begin{cases}', '\\end{cases}', '```',
    }
    local actual, changed = math.normalize(input)
    assert.is_false(changed)
    assert.same(input, actual)
  end)

  it('leaves unmatched environments alone', function()
    local input = { '\\begin{cases}', 'x = 1' }
    local actual, changed = math.normalize(input)
    assert.is_false(changed)
    assert.same(input, actual)
  end)

  it('wraps environments after single-line display math', function()
    local input = {
      '$$T = I$$', '\\[x\\]', 'a \\\\[4pt]', '\\begin{cases}', 'x = 1', '\\end{cases}',
    }
    local actual, changed = math.normalize(input)
    assert.is_true(changed)
    assert.same({
      '$$T = I$$', '\\[x\\]', 'a \\\\[4pt]', '$$', '\\begin{cases}', 'x = 1', '\\end{cases}', '$$',
    }, actual)
  end)

  it('finds multi-line display blocks outside fences', function()
    assert.same({{1, 3}}, math.display_blocks({
      '$$a$$', '$$', 'x', '$$', '```', '$$ y', 'z $$', '```',
    }))
  end)

  it('conceals rendered display blocks except under the cursor', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'text', '$$', 'x', '$$', '$$ y', 'z $$', 'raw', '$$', 'q', '$$'})
    local markdown = vim.api.nvim_create_namespace('render-markdown.nvim')
    for _, row in ipairs({1, 4}) do
      vim.api.nvim_buf_set_extmark(buf, markdown, row, 0, {virt_lines = {{{'rendered'}}}, virt_lines_above = true})
    end
    local win = vim.api.nvim_open_win(buf, false, {relative = 'editor', row = 0, col = 0, width = 20, height = 10})
    vim.api.nvim_win_set_cursor(win, {6, 0})
    math.conceal_display_math(buf, win)
    local ns = vim.api.nvim_get_namespaces()['brightspace.notebook_math']
    local hidden = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {details = true})) do
      hidden[#hidden + 1] = mark[2] .. (mark[4].conceal_lines and 'L' or 'C')
    end
    -- Block at rows 1-3 is rendered and hidden; rows 4-5 hold the cursor; rows 7-9 were not rendered.
    assert.same({'1C', '2L', '3L'}, hidden)
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, {force = true})
  end)
end)
