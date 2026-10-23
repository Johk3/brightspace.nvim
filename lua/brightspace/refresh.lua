local M = {}
local store = require('brightspace.store')
local courses = require('brightspace.model.courses')
local content = require('brightspace.model.content')
local news = require('brightspace.model.news')
local time = require('brightspace.time')
local pieces = {'toc','news','dropbox','quizzes','overview'}

function M.items(state,id)
  local items = {}
  for _,item in ipairs(content.flatten(state.trees[id] or {})) do
    if item.kind ~= 'module' then items[#items+1]=item end
  end
  vim.list_extend(items,state.news[id] or {})
  if state.info[id] then items[#items+1]=state.info[id] end
  return items
end
function M.rebuild(state)
  state.groups=courses.group(state.courses)
  state.new_items,state.new_counts={},{}
  for _,course in ipairs(state.courses) do
    local count=0
    for _,item in ipairs(M.items(state,course.id)) do
      item.course_code=course.code
      if store.is_new(item) then
        count=count+1
        if course.current then state.new_items[#state.new_items+1]=item end
      end
    end
    state.new_counts[course.id]=count
  end
  table.sort(state.new_items,function(a,b)
    local x,y=type(a.modified)=='number' and a.modified or 0,type(b.modified)=='number' and b.modified or 0
    return x==y and a.key<b.key or x>y
  end)
  state.deadlines=require('brightspace.model.deadlines').build(state.courses,state.per_course,state.calendar,
    os.time(),require('brightspace.config').get().deadline_days)
  local found=false
  for _,c in ipairs(state.courses) do if c.id==state.selected_id then found=true end end
  if not found then
    local first=courses.current(state.courses)[1] or state.courses[1]
    state.selected_id=first and first.id
  end
end
local function apply(state,name,id,data)
  if name=='courses' then state.courses=courses.normalize(data,os.time())
  elseif name=='calendar' then state.calendar=data.Objects or data.Items or data
  elseif name=='toc' then state.trees[id]=content.from_toc(id,data)
  elseif name=='news' then state.news[id]=news.from_api(id,data)
  elseif name=='overview' then state.info[id]=news.overview(id,data)
  else
    state.per_course[id]=state.per_course[id] or {}
    state.per_course[id][name]=data.Objects or data.Items or data
  end
end
function M.load_cached(state)
  store.seen_load()
  local raw=store.cache_get('courses')
  if raw then apply(state,'courses',nil,raw) end
  for _,course in ipairs(state.courses) do
    for _,name in ipairs(pieces) do
      local value=store.cache_get(name..':'..course.id)
      if value then apply(state,name,course.id,value) end
    end
  end
  local calendar=store.cache_get('calendar')
  if calendar then apply(state,'calendar',nil,calendar) end
  M.rebuild(state)
end
function M.cancel(state)
  state.generation=state.generation+1
  state.cancels=(state.cancels or 0)+1
  state.loading=false
end
local function notify_error(err)
  local message=err=='network_error' and 'offline, showing cached data' or err
  vim.notify('Brightspace: '..tostring(message),vim.log.levels.WARN)
end
local function execute(state,on_update,opts)
  if state.loading then return end
  state.loading=true
  state.generation=state.generation+1
  local generation=state.generation
  local api=require('brightspace.api')
  local ttl=require('brightspace.config').get().cache_ttl
  local function valid() return generation==state.generation end
  -- Coalesce per-job redraws: a burst of responses rebuilds and redraws once.
  local dirty=false
  local function flush() dirty=false; M.rebuild(state); on_update() end
  local function update()
    if dirty then return end
    dirty=true
    vim.schedule(function() if dirty and valid() then flush() end end)
  end
  local successes,errors=0,{}
  local function fetch(name,id,cb)
    local key=name..(id and ':'..id or '')
    local cached,age=store.cache_get(key)
    if not opts.force and cached and age<ttl and pcall(apply,state,name,id,cached) then
      successes=successes+1
      return cb(nil)
    end
    local function settle(err,data)
      if err then return err end
      if type(data)~='table' or not pcall(apply,state,name,id,data) then return 'bad_response' end
      successes=successes+1
      if id and (name=='toc' or name=='news' or name=='overview') then
        local items = name=='toc' and content.flatten(state.trees[id])
          or (name=='news' and state.news[id] or (state.info[id] and {state.info[id]} or {}))
        store.baseline(id..':'..name,items,os.time())
      end
      store.cache_put(key,data)
    end
    local function done(err,data)
      vim.schedule(function()
        if not valid() then return end
        -- A throwing apply or disk write must still settle the job, or loading never ends.
        local ok,result=pcall(settle,err,data)
        if ok then err=result else err='storage_error' end
        if err then errors[#errors+1]=err end
        cb(err)
      end)
    end
    if name=='courses' then api.courses(done)
    elseif name=='calendar' then
      local now=os.time()
      local ids={}
      for _,course in ipairs(courses.current(state.courses)) do ids[#ids+1]=course.id end
      api.calendar(time.iso(now),time.iso(now+require('brightspace.config').get().deadline_days*86400),done,ids)
    else api[name](id,done) end
  end
  local function finish()
    if not valid() then return end
    state.loading=false
    state.errors=errors
    flush()
    if #errors>0 then
      if successes==0 then notify_error(errors[1])
      else vim.notify('Brightspace: some data unavailable ('..table.concat(vim.fn.uniq(vim.fn.sort(vim.deepcopy(errors))),', ')..')',vim.log.levels.WARN) end
    end
  end
  local function populate()
    local jobs={}
    for _,course in ipairs(state.courses) do
      if (opts.course_id and course.id==opts.course_id) or (not opts.course_id and course.current) then
        local names=opts.course_id and {'toc','news','overview'} or pieces
        for _,name in ipairs(names) do jobs[#jobs+1]={name=name,id=course.id} end
      end
    end
    if not opts.course_id then jobs[#jobs+1]={name='calendar'} end
    local index,active,completed=1,0,0
    local pumping=false
    local pump
    pump=function()
      if pumping or not valid() then return end
      pumping=true
      while active<4 and index<=#jobs do
        local job=jobs[index]; index=index+1; active=active+1
        fetch(job.name,job.id,function(err)
          active=active-1; completed=completed+1
          update()
          if not pumping then pump() end
        end)
      end
      pumping=false
      if completed==#jobs then finish() end
    end
    pump()
  end
  require('brightspace.auth.session').ensure(function(err)
    if not valid() then return end
    if err then state.loading=false; notify_error(err); flush(); return end
    if opts.course_id then return populate() end
    fetch('courses',nil,function(course_err)
      if course_err then return finish() end
      update(); populate()
    end)
  end)
end
function M.run(state,on_update,opts) execute(state,on_update,opts or {}) end
function M.select(state,id,on_update)
  state.selected_id=id
  on_update()
  if state.loading then
    -- The active refresh owns the queue; load the course after it settles unless
    -- the workspace was cancelled or another course was selected meanwhile.
    local cancels=state.cancels
    local function later()
      if state.cancels~=cancels or state.selected_id~=id then return end
      if state.loading then return vim.defer_fn(later,50) end
      execute(state,on_update,{course_id=id})
    end
    return vim.defer_fn(later,50)
  end
  execute(state,on_update,{course_id=id})
end
return M
