local session=require('brightspace.auth.session')
describe('api',function()
  local saved, saved_html, api
  before_each(function() saved=session.get_json; saved_html=session.html; package.loaded['brightspace.api']=nil; api=require('brightspace.api') end)
  after_each(function() session.get_json=saved; session.html=saved_html end)
  it('discovers highest numeric version and follows bookmarks',function()
    local paths={}
    session.get_json=function(path,cb)
      paths[#paths+1]=path
      if path=='/d2l/api/versions/' then return cb(nil,{{ProductCode='lp',SupportedVersions={'1.9','1.49','1.10'}},{ProductCode='le',SupportedVersions={'1.82'}}}) end
      if path:find('bookmark=',1,true) then return cb(nil,{Items={{Id=2}},PagingInfo={HasMoreItems=false}}) end
      cb(nil,{Items={{Id=1}},PagingInfo={HasMoreItems=true,Bookmark='a b'}})
    end
    api.courses(function(err,items) assert.is_nil(err); assert.equals(2,#items) end)
    assert.is_truthy(paths[2]:find('/lp/1.49/',1,true))
    assert.is_truthy(paths[3]:find('bookmark=a%20b',1,true))
  end)
  it('adds required calendar course ids and follows Next pages',function()
    local paths={}
    session.get_json=function(path,cb)
      paths[#paths+1]=path
      if path=='/d2l/api/versions/' then return cb(nil,{}) end
      if path=='/next-events' then return cb(nil,{Objects={{Id=2}},Next=vim.NIL}) end
      cb(nil,{Objects={{Id=1}},Next='/next-events'})
    end
    local events
    api.calendar('2026-10-16T00:00:00Z','2026-11-16T00:00:00Z',function(err,data)
      assert.is_nil(err); events=data
    end,{100001,100002})
    assert.equals(2,#events)
    assert.is_truthy(paths[2]:find('orgUnitIdsCSV=100001%2C100002',1,true))
    assert.equals('/next-events',paths[3])
  end)
  it('derives calendar ids for callers without an explicit course list',function()
    session.get_json=function(path,cb)
      if path=='/d2l/api/versions/' then return cb(nil,{}) end
      if path:find('myenrollments',1,true) then return cb(nil,{Items={
        {OrgUnit={Id=100001,Type={Id=3}},Access={IsActive=true}},
        {OrgUnit={Id=100002,Type={Id=3}},Access={IsActive=false}},
      }}) end
      assert.is_truthy(path:find('orgUnitIdsCSV=100001',1,true))
      assert.is_nil(path:find('100002',1,true))
      cb(nil,{Objects={}})
    end
    local done=false
    api.calendar('from','to',function(err,data) assert.is_nil(err); assert.same({},data); done=true end)
    assert.is_true(done)
  end)
  it('returns no calendar data without requesting an empty course set',function()
    session.get_json=function() error('no request for empty ids') end
    local done=false
    api.calendar('from','to',function(err,data) assert.is_nil(err); assert.same({},data); done=true end,{})
    assert.is_true(done)
  end)
  it('normalizes an absent overview and preserves other errors',function()
    local failure='http_404'
    session.get_json=function(path,cb)
      if path=='/d2l/api/versions/' then return cb(nil,{}) end
      cb(failure)
    end
    api.overview(100001,function(err,data) assert.is_nil(err); assert.same({},data) end)
    failure='http_500'
    api.overview(100001,function(err) assert.equals('http_500',err) end)
  end)
  it('reads HTML topic files through the authenticated HTML interface',function()
    session.get_json=function(path,cb) assert.equals('/d2l/api/versions/',path); cb(nil,{}) end
    session.html=function(path,cb)
      assert.equals('/d2l/api/le/1.82/100001/content/topics/100002/file',path)
      cb(nil,'<h1>Example</h1>')
    end
    local result
    api.topic_html(100001,100002,function(err,data) assert.is_nil(err); result=data end)
    assert.equals('<h1>Example</h1>',result)
  end)
  it('rejects cyclic next pages',function()
    session.get_json=function(path,cb)
      if path=='/d2l/api/versions/' then return cb(nil,{}) end
      cb(nil,{Objects={},Next=path})
    end
    local err
    api.quizzes(100001,function(e) err=e end)
    assert.equals('bad_paging',err)
  end)
end)

describe('documented version discovery',function()
  it('selects highest ApiVersion entry independently of order',function()
    local saved=session.get_json
    package.loaded['brightspace.api']=nil
    local api=require('brightspace.api')
    local requested
    session.get_json=function(path,cb)
      if path=='/d2l/api/versions/' then return cb(nil,{{ProductCode='le',Version='1.90'},{ProductCode='le',Version='1.82'}}) end
      requested=path; cb(nil,{})
    end
    api.toc(100001,function() end)
    session.get_json=saved
    assert.is_truthy(requested:find('/le/1.90/',1,true))
  end)
end)
