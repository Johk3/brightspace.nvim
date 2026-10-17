local session=require('brightspace.auth.session')
local http=require('brightspace.http')
local M={}
local versions, discovering
-- Conservative compatibility defaults until this installation's live spike runs.
local fallback={lp='1.49',le='1.82'}
local function newer(a,b)
  local am,an=tostring(a):match('^(%d+)%.(%d+)$')
  local bm,bn=tostring(b):match('^(%d+)%.(%d+)$')
  return am and (not bm or tonumber(am)>tonumber(bm) or (tonumber(am)==tonumber(bm) and tonumber(an)>tonumber(bn)))
end
local function discover(cb)
  if versions then return cb(nil,versions) end
  if discovering then discovering[#discovering+1]=cb; return end
  discovering={cb}
  session.get_json('/d2l/api/versions/',function(err,data)
    local chosen=vim.deepcopy(fallback)
    local discovered={}
    if not err then
      for _,product in ipairs(data) do
        if fallback[product.ProductCode] then
          local highest=product.Version or product.LatestVersion
          for _,value in ipairs(product.SupportedVersions or {}) do
            local v=type(value)=='table' and value.Version or value
            if v and newer(v,highest) then highest=tostring(v) end
          end
          if highest and newer(highest,discovered[product.ProductCode]) then
            discovered[product.ProductCode]=highest
            chosen[product.ProductCode]=highest
          end
        end
      end
    end
    versions=chosen
    local callbacks=discovering; discovering=nil
    -- Discovery is anonymous on Brightspace; temporary failure uses compatibility routes.
    for _,done in ipairs(callbacks) do done(nil,chosen) end
  end)
end
local function route(product,suffix,cb,download)
  discover(function(_,v)
    local path='/d2l/api/'..product..'/'..v[product]..'/'..suffix
    if download then session.download(path,download,cb) else session.get_json(path,cb) end
  end)
end
local function id(value)
  local s=tostring(value)
  if not s:match('^%d+$') then return nil end
  return s
end
local function course_route(ou,suffix,cb,dest)
  ou=id(ou)
  if not ou then return cb('invalid_id') end
  route('le',ou..'/'..suffix,cb,dest)
end
local function collect(first,bookmark,cb)
  local out,seen={},{}
  local function page(path)
    path=session.local_path(path)
    if not path then return cb('invalid_path') end
    if seen[path] or vim.tbl_count(seen)>=1000 then return cb('bad_paging') end
    seen[path]=true
    session.get_json(path,function(err,data)
      if err then return cb(err) end
      local items=data.Items or data.Objects or data
      if type(items)~='table' then return cb('bad_response') end
      vim.list_extend(out,items)
      local info=data.PagingInfo
      if info and info.HasMoreItems then
        if info.Bookmark==nil or tostring(info.Bookmark)=='' then return cb('bad_paging') end
        return page(first..(first:find('?',1,true) and '&' or '?')..'bookmark='..http.urlencode(info.Bookmark))
      end
      if not bookmark and data.Next and data.Next~=vim.NIL and data.Next~='' then
        if type(data.Next)~='string' then return cb('bad_paging') end
        local next_path=data.Next
        if next_path:sub(1,1)=='?' then next_path=path:gsub('%?.*$','')..next_path end
        return page(next_path)
      end
      cb(nil,out)
    end)
  end
  page(first)
end
function M.courses(cb)
  discover(function(_,v) collect('/d2l/api/lp/'..v.lp..'/enrollments/myenrollments/?orgUnitTypeId=3',true,cb) end)
end
function M.toc(ou,cb) course_route(ou,'content/toc',cb) end
function M.news(ou,cb) course_route(ou,'news/',cb) end
function M.dropbox(ou,cb) course_route(ou,'dropbox/folders/',cb) end
function M.overview(ou,cb)
  course_route(ou,'overview',function(err,data)
    if err=='http_404' then return cb(nil,{}) end
    cb(err,data)
  end)
end
function M.quizzes(ou,cb)
  ou=id(ou); if not ou then return cb('invalid_id') end
  discover(function(_,v) collect('/d2l/api/le/'..v.le..'/'..ou..'/quizzes/',false,cb) end)
end
function M.calendar(from,to,cb,course_ids)
  if course_ids==nil then
    return M.courses(function(err,enrollments)
      if err then return cb(err) end
      local courses=require('brightspace.model.courses')
      local ids={}
      for _,course in ipairs(courses.current(courses.normalize(enrollments,os.time()))) do
        ids[#ids+1]=course.id
      end
      M.calendar(from,to,cb,ids)
    end)
  end
  local ids={}
  for _,course_id in ipairs(course_ids) do
    local valid=id(course_id)
    if not valid then return cb('invalid_id') end
    ids[#ids+1]=valid
  end
  if #ids==0 then return cb(nil,{}) end
  discover(function(_,v)
    local path='/d2l/api/le/'..v.le..'/calendar/events/myEvents/?orgUnitIdsCSV='
      ..http.urlencode(table.concat(ids,','))..'&startDateTime='..http.urlencode(from)
      ..'&endDateTime='..http.urlencode(to)
    collect(path,false,cb)
  end)
end
function M.topic_file(ou,topic,dest,cb)
  topic=id(topic); if not topic then return cb('invalid_id') end
  course_route(ou,'content/topics/'..topic..'/file',cb,dest)
end
function M.topic_html(ou,topic,cb)
  ou,topic=id(ou),id(topic)
  if not ou or not topic then return cb('invalid_id') end
  discover(function(_,v)
    session.html('/d2l/api/le/'..v.le..'/'..ou..'/content/topics/'..topic..'/file',cb)
  end)
end
return M
