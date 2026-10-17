describe('commands',function()
  local commands, originals, notices, root, old_cache
  before_each(function()
    originals={}
    for _,name in ipairs({'brightspace.auth.session','brightspace.ui.workspace','brightspace.refresh','brightspace.commands'}) do originals[name]=package.loaded[name] end
    local notify=vim.notify
    originals.notify=notify; notices={}; vim.notify=function(msg) notices[#notices+1]=msg end
    root=vim.fn.tempname(); old_cache=vim.env.BRIGHTSPACE_CACHE_DIR; vim.env.BRIGHTSPACE_CACHE_DIR=root
    package.loaded['brightspace.commands']=nil
    package.loaded['brightspace.ui.workspace']={close=function() end,is_open=function() return false end}
    package.loaded['brightspace.refresh']={cancel=function() end}
    commands=require('brightspace.commands')
  end)
  after_each(function()
    for _,name in ipairs({'brightspace.auth.session','brightspace.ui.workspace','brightspace.refresh','brightspace.commands'}) do package.loaded[name]=originals[name] end
    vim.notify=originals.notify; vim.env.BRIGHTSPACE_CACHE_DIR=old_cache; vim.fn.delete(root,'rf')
  end)
  it('lists valid commands for an unknown subcommand',function()
    commands.run('bogus')
    assert.equals(1,#notices)
    assert.is_truthy(notices[1]:find('logout',1,true))
  end)
  it('logout clears downloaded and JSON caches after clearing session',function()
    local logged_out=false
    package.loaded['brightspace.auth.session']={logout=function(cb) logged_out=true; cb(nil) end}
    require('brightspace.store').cache_put('courses',{})
    vim.fn.mkdir(root..'/files','p'); vim.fn.writefile({'private'},root..'/files/example.pdf')
    commands.run('logout')
    assert.is_true(logged_out)
    assert.is_nil(require('brightspace.store').cache_get('courses'))
    assert.equals(0,vim.fn.isdirectory(root..'/files'))
  end)
end)
