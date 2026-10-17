describe('background refresh',function()
  local refresh,state,store,root,old,api,original_api,original_session,original_notify,notices
  local row={OrgUnit={Id=100001,Type={Id=3},Name='Example (2026/27 Q1)',Code='TEST1001'},Access={}}
  before_each(function()
    root=vim.fn.tempname(); old={vim.env.BRIGHTSPACE_CACHE_DIR,vim.env.BRIGHTSPACE_DATA_DIR}
    vim.env.BRIGHTSPACE_CACHE_DIR,vim.env.BRIGHTSPACE_DATA_DIR=root..'/cache',root..'/data'
    original_api,original_session=package.loaded['brightspace.api'],package.loaded['brightspace.auth.session']
    original_notify=vim.notify; notices={}; vim.notify=function(msg) notices[#notices+1]=msg end
    api={courses=function(cb) cb(nil,{row}) end,calendar=function(_,_,cb) cb(nil,{}) end}
    for _,name in ipairs({'toc','news','dropbox','quizzes','overview'}) do api[name]=function(_,cb) cb(nil,{}) end end
    package.loaded['brightspace.api']=api
    package.loaded['brightspace.auth.session']={ensure=function(cb) cb(nil) end}
    package.loaded['brightspace.refresh']=nil
    refresh=require('brightspace.refresh'); state=require('brightspace.state').new()
    store=require('brightspace.store'); store.seen_load()
  end)
  after_each(function()
    package.loaded['brightspace.api'],package.loaded['brightspace.auth.session']=original_api,original_session
    vim.notify=original_notify
    vim.env.BRIGHTSPACE_CACHE_DIR,vim.env.BRIGHTSPACE_DATA_DIR=old[1],old[2]
    vim.fn.delete(root,'rf')
  end)
  local function finish() assert.is_true(vim.wait(1000,function() return not state.loading end)) end
  it('keeps cached data when refresh fails and warns once',function()
    store.cache_put('courses',{row}); refresh.load_cached(state)
    api.courses=function(cb) cb('network_error') end
    refresh.run(state,function() end,{force=true}); finish()
    assert.equals('TEST1001',state.courses[1].code)
    assert.equals(1,#notices)
  end)
  it('fetches current courses only and honors cache TTL',function()
    local calls={}
    api.courses=function(cb) cb(nil,{row,{OrgUnit={Id=100002,Type={Id=3},Name='Past (2025/26 Q1)'}}}) end
    api.toc=function(id,cb) calls[#calls+1]=id; cb(nil,{Modules={}}) end
    refresh.run(state,function() end); finish()
    assert.same({100001},calls)
    refresh.run(state,function() end); finish()
    assert.same({100001},calls)
    refresh.select(state,100002,function() end)
    assert.is_true(vim.wait(1000,function() return #calls==2 end))
    assert.same({100001,100002},calls)
  end)
  it('caps concurrent requests at four and baselines all first-load sources together',function()
    local active,peak=0,0
    for _,name in ipairs({'toc','news','dropbox','quizzes','overview'}) do
      api[name]=function(_,cb)
        active=active+1; peak=math.max(peak,active)
        vim.defer_fn(function()
          active=active-1
          cb(nil,name=='news' and {{Id=1,Title='Old announcement',LastModifiedDate='2020-01-01T00:00:00Z'}} or {})
        end,5)
      end
    end
    refresh.run(state,function() end); finish()
    assert.equals(4,peak)
    assert.equals(0,#state.new_items)
  end)
  it('baselines historical content even when optional deadline sources fail',function()
    api.quizzes=function(_,cb) cb('http_403') end
    api.news=function(_,cb) cb(nil,{{Id=1,Title='Old',LastModifiedDate='2020-01-01T00:00:00Z'}}) end
    refresh.run(state,function() end); finish()
    assert.equals(0,#state.new_items)
  end)
  it('cancels stale responses before logout can repopulate the cache',function()
    local pending
    api.courses=function(cb) pending=cb end
    refresh.run(state,function() end)
    refresh.cancel(state)
    pending(nil,{row})
    assert.is_nil(store.cache_get('courses'))
    assert.is_false(state.loading)
  end)
end)
