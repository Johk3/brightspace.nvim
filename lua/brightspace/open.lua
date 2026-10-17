local M = {}
local pending = {}
local function warn(err) vim.notify('Brightspace: '..tostring(err),vim.log.levels.WARN) end
local function mark(item,cb)
  require('brightspace.store').mark_seen(item)
  if cb then cb() end
end
local function launch(cmd,item,cb)
  local ok = pcall(vim.system,cmd,{detach=true},function(result)
    if result.code~=0 then vim.schedule(function() warn('viewer exited with '..result.code) end) end
  end)
  if ok then mark(item,cb) else warn('could not start viewer') end
end
local function float(item,body,cb)
  local width=math.max(10,math.min(100,math.floor(vim.o.columns*.8)))
  local lines=require('brightspace.html2text').render(body,width-2)
  local height=math.max(1,math.min(#lines,math.floor(vim.o.lines*.75)))
  local buf=vim.api.nvim_create_buf(false,true)
  vim.bo[buf].bufhidden='wipe'
  vim.api.nvim_buf_set_lines(buf,0,-1,false,lines)
  vim.bo[buf].modifiable=false
  local win=vim.api.nvim_open_win(buf,true,{relative='editor',width=width,height=height,
    row=math.max(0,math.floor((vim.o.lines-height)/2)-1),col=math.max(0,math.floor((vim.o.columns-width)/2)),
    style='minimal',border='rounded',title=' '..(item.title or 'Brightspace'):gsub('[%c]',' ')..' '})
  vim.wo[win].wrap=true
  for _,key in ipairs({'q','<Esc>'}) do
    vim.keymap.set('n',key,function() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win,true) end end,{buffer=buf})
  end
  mark(item,cb)
end
local function absolute(url)
  if type(url)~='string' then return nil end
  if url:sub(1,1)=='/' and url:sub(1,2)~='//' then url=require('brightspace.config').get().base_url..url end
  if not url:match('^https?://') or url:find('%c') then return nil end
  return url
end
local function viewer(path,item,cb)
  local command=require('brightspace.config').get().viewer
  local args=type(command)=='table' and vim.deepcopy(command) or {command}
  args[#args+1]=path
  launch(args,item,cb)
end
function M.item(item,cb)
  if vim.in_fast_event() then return vim.schedule(function() M.item(item,cb) end) end
  if item.kind=='module' then return end
  if item.body_html or item.kind=='news' or item.kind=='info' then return float(item,item.body_html or '',cb) end
  if item.kind=='deadline' then
    if item.url then
      local url=absolute(item.url)
      if url then return launch({'xdg-open',url},item,cb) end
    end
    return float(item,'<p>'..(item.title or 'Deadline')..'</p><p>Due: '..os.date('%c',item.due)..'</p>',cb)
  end
  if item.file_type~='File' then
    local url=absolute(item.url)
    if not url then return warn('unsupported link') end
    return launch({'xdg-open',url},item,cb)
  end
  local paths=require('brightspace.paths')
  local dir=paths.cache()..'/files/'..tostring(item.course_id):gsub('[^%w_-]','_')
  vim.fn.mkdir(dir,'p','0700')
  local name=tostring(item.topic_id):gsub('[^%w_-]','_')..'-'..tostring(item.modified or 0):gsub('[^%w_-]','_')
  local prefix=dir..'/'..name
  for _,path in ipairs(vim.fn.glob(prefix..'.*',false,true)) do
    if not path:match('%.part$') then
      if path:match('%.html?$') then
        return float(item,table.concat(vim.fn.readfile(path),'\n'),cb)
      end
      return viewer(path,item,cb)
    end
  end
  if pending[prefix] then return end
  pending[prefix]=true
  local source_path = (item.url or ''):gsub('[?#].*$', ''):lower()
  if source_path:match('%.html?$') then
    return require('brightspace.api').topic_html(item.course_id,item.topic_id,function(err,body)
      vim.schedule(function()
        pending[prefix]=nil
        if err then return warn(err) end
        local path=prefix..'.html'
        local fd=vim.uv.fs_open(path,'w',384)
        if not fd then return warn('could not cache page') end
        vim.uv.fs_write(fd,body,0)
        vim.uv.fs_close(fd)
        float(item,body,cb)
      end)
    end)
  end
  local dest=prefix..'.part'
  require('brightspace.api').topic_file(item.course_id,item.topic_id,dest,function(err,meta)
    vim.schedule(function()
      pending[prefix]=nil
      if err then vim.fn.delete(dest); return warn(err) end
      local ext=meta.filename and meta.filename:match('%.([%w]+)$')
      local mime=(meta.content_type or ''):match('^[^;]+')
      ext=ext or ({['application/pdf']='pdf',['text/plain']='txt',['image/png']='png',['image/jpeg']='jpg'})[mime] or 'bin'
      local path=prefix..'.'..ext:lower()
      local ok=vim.uv.fs_rename(dest,path)
      if not ok then return warn('could not cache file') end
      if ext=='html' or ext=='htm' then return float(item,table.concat(vim.fn.readfile(path),'\n'),cb) end
      viewer(path,item,cb)
    end)
  end)
end
return M
