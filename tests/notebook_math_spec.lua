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
end)
