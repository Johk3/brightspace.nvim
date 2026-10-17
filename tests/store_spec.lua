local store = require('brightspace.store')
describe('disk store', function()
  local root, old_data, old_cache
  before_each(function()
    root = vim.fn.tempname()
    old_data, old_cache = vim.env.BRIGHTSPACE_DATA_DIR, vim.env.BRIGHTSPACE_CACHE_DIR
    vim.env.BRIGHTSPACE_DATA_DIR, vim.env.BRIGHTSPACE_CACHE_DIR = root..'/data', root..'/cache'
    store.seen_load()
  end)
  after_each(function()
    vim.fn.delete(root, 'rf')
    vim.env.BRIGHTSPACE_DATA_DIR, vim.env.BRIGHTSPACE_CACHE_DIR = old_data, old_cache
  end)
  it('baselines old items and preserves seen markers across reloads', function()
    local old = {key='topic:1:1',modified=100}
    local recent = {key='topic:1:2',modified=1000000}
    store.baseline(1, {old,recent}, 1000001)
    assert.is_false(store.is_new(old))
    assert.is_true(store.is_new(recent))
    store.mark_seen(recent)
    store.seen_load()
    assert.is_false(store.is_new(recent))
    recent.modified = 1000002
    assert.is_true(store.is_new(recent))
    store.baseline(1, {{key='topic:1:3',modified=1}}, 1000001)
    assert.is_true(store.is_new({key='topic:1:3',modified=1}))
  end)
  it('round trips cache and treats corrupt data as missing', function()
    store.cache_put('toc:1', {title='Example'})
    local value, age = store.cache_get('toc:1')
    assert.equals('Example', value.title)
    assert.is_true(age >= 0 and age < 2)
    assert.is_nil(store.cache_get('absent'))
    vim.fn.writefile({'garbage'}, root..'/data/seen.json')
    store.seen_load()
    assert.is_true(store.is_new({key='x'}))
  end)
end)
