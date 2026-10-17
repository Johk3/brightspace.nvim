local http = require('brightspace.http')
local login = require('brightspace.auth.login')
local keyring = require('brightspace.auth.keyring')
local M = {}
local authenticated, memory, flight, timer = false, nil, nil, nil
local generation, revision = 0, 0

local function main(fn)
  return function(...)
    local args, n = {...}, select("#", ...)
    if vim.in_fast_event() then vim.schedule(function() fn(unpack(args, 1, n)) end) else fn(unpack(args, 1, n)) end
  end
end
local function base() return require('brightspace.config').get().base_url:gsub('/+$','') end
local function local_path(path)
  if type(path) ~= 'string' then return nil end
  local origin = base()
  if path:sub(1,#origin+1) == origin..'/' then path=path:sub(#origin+1) end
  if path:sub(1,1) ~= '/' or path:sub(1,2)=='//' or path:find('[%c\\]') then return nil end
  return path
end
M.local_path = local_path

function M.ensure(cb, force_login)
  if vim.in_fast_event() then return vim.schedule(function() M.ensure(cb, force_login) end) end
  if authenticated and not force_login then return cb(nil) end
  if flight then flight[#flight+1]=cb; return end
  flight={cb}
  local token=generation
  local function active() return token==generation end
  local function finish(err)
    if not active() then return end
    authenticated=not err
    if not err then revision=revision+1 end
    local callbacks=flight; flight=nil
    for _,done in ipairs(callbacks) do done(err) end
  end
  local attempt, prompt
  function prompt(reprompted)
    if not active() then return end
    vim.ui.input({prompt='Brightspace NetID: '}, main(function(netid)
      if not active() then return end
      if not netid or netid=='' then return finish('cancelled') end
      local password=vim.fn.inputsecret('Brightspace password: ')
      if not password or password=='' then return finish('cancelled') end
      memory={netid=netid,password=password}
      local function go() if active() then attempt(memory,reprompted) end end
      if keyring.available() then keyring.store(netid,password,main(function(err)
        if err then return finish('keyring_error') end
        go()
      end)) else go() end
    end))
  end
  function attempt(creds, reprompted)
    if not active() then return end
    login.run(creds,main(function(err)
      if not active() then return end
      if err=='bad_credentials' and not reprompted then
        vim.notify('TU Delft login rejected credentials',vim.log.levels.WARN)
        memory=nil
        return prompt(true)
      end
      finish(err)
    end))
  end
  local function credentials()
  if memory then return attempt(memory,false) end
  if not keyring.available() then return prompt(false) end
  keyring.get(main(function(err,creds)
    if not active() then return end
    if err then return finish('keyring_error') end
    if creds then memory=creds; attempt(creds,false) else prompt(false) end
  end))
  end
  if not force_login and vim.uv.fs_stat(require("brightspace.paths").cookie_jar()) then
    return http.request({method="GET",url=base().."/d2l/api/lp/1.0/users/whoami",follow=false},main(function(err,res)
      if not active() then return end
      if not err and res.status==200 then
        local ok,data=pcall(vim.json.decode,res.body or "")
        if ok and type(data)=="table" then return finish(nil) end
      end
      credentials()
    end))
  end
  credentials()
end

local function expired(res)
  return res.status==401 or res.status==403 or (res.status==302 and (res.location or (res.headers or {}).location or ''):find('/d2l/login',1,true))
end
local function request(path,dest,cb)
  if vim.in_fast_event() then return vim.schedule(function() request(path,dest,cb) end) end
  path=local_path(path)
  if not path then return cb('invalid_path') end
  local token=generation
  local function send(retried, current_path, redirects)
    current_path=current_path or path
    redirects=redirects or 0
    local sent_revision=revision
    http.request({method='GET',url=base()..current_path,output=dest,follow=false},main(function(err,res)
      if token~=generation then
        if dest then vim.uv.fs_unlink(dest) end
        return cb('logged_out')
      end
      if err then return cb('network_error') end
      if expired(res) then
        if dest then vim.uv.fs_unlink(dest) end
        if retried then return cb('session_expired') end
        -- A different request may already have renewed the shared session.
        if revision~=sent_revision then return send(true, current_path, redirects) end
        authenticated=false
        return M.ensure(function(auth_err)
          if auth_err then return cb(auth_err) end
          send(true, current_path, redirects)
        end, true)
      end
      local location=res.location or (res.headers or {}).location
      if (res.status==301 or res.status==302 or res.status==303 or res.status==307 or res.status==308) and location then
        if redirects>=5 then return cb('too_many_redirects') end
        if not location:match('^%a[%w+.-]*:') and location:sub(1,1)~='/' then
          location=current_path:gsub('%?.*$',''):match('^(.*)/')..'/'..location
        end
        local next_path=local_path(location)
        if not next_path then
          if dest then vim.uv.fs_unlink(dest) end
          return cb('invalid_path')
        end
        return send(retried,next_path,redirects+1)
      end
      if res.status~=200 then
        if dest then vim.uv.fs_unlink(dest) end
        return cb('http_'..tostring(res.status))
      end
      cb(nil,res)
    end))
  end
  send(false)
end
function M.get_json(path,cb)
  request(path,nil,function(err,res)
    if err then return cb(err) end
    local ok,data=pcall(vim.json.decode,res.body or '')
    if not ok or type(data)~='table' then return cb('bad_response') end
    cb(nil,data)
  end)
end
-- HTML topics share the authenticated transport, but never expose login pages
-- as course content. Page scripts are inspected as text and never executed.
function M.html(path,cb)
  request(path,nil,function(err,res)
    if err then return cb(err) end
    local content_type=((res.headers or {})['content-type'] or ''):lower()
    if not content_type:find('text/html',1,true) and not content_type:find('application/xhtml+xml',1,true) then
      return cb('bad_response')
    end
    local body=res.body or ''
    local lower=body:lower()
    local function login_target(url)
      url=url:lower()
      return url:find('/d2l/login',1,true) or url:find('/d2l/lp/auth/',1,true)
        or url:find('://login.tudelft.nl/',1,true)
    end
    if login_target(res.url or '') then return cb('session_expired') end
    local forms=require('brightspace.auth.forms').parse(body,base()..path)
    for _,form in ipairs(forms) do
      if form.inputs.password~=nil or form.inputs.SAMLRequest~=nil or form.inputs.SAMLResponse~=nil
        or login_target(form.action) then return cb('session_expired') end
    end
    for input in lower:gmatch('<input%s[^>]*>') do
      if input:match([[type%s*=%s*["']?password]]) then return cb('session_expired') end
    end
    for target in lower:gmatch([[location[^=;>]*=%s*["']([^"']+)]]) do
      if login_target(target) then return cb('session_expired') end
    end
    for target in lower:gmatch([[location%.[%w_]+%s*%(%s*["']([^"']+)]]) do
      if login_target(target) then return cb('session_expired') end
    end
    for meta in lower:gmatch('<meta%s[^>]*>') do
      if meta:find('refresh',1,true) then
        local target=meta:match([[url%s*=%s*["']?([^"'>%s]+)]])
        if target and login_target(target) then return cb('session_expired') end
      end
    end
    cb(nil,body)
  end)
end
function M.download(path,dest,cb)
  request(path,dest,function(err,res)
    if err then return cb(err) end
    local headers=res.headers or {}
    local content_type=headers['content-type'] or ''
    if content_type:lower():find('text/html',1,true) or content_type:lower():find('application/xhtml+xml',1,true) then
      vim.uv.fs_unlink(dest)
      return cb('not_a_file')
    end
    local disposition=headers['content-disposition'] or ''
    local filename=disposition:match('filename="([^"]+)"') or disposition:match('filename=([^;]+)')
    if filename then filename=filename:gsub('.*[/\\]',''):gsub('%c','') end
    cb(nil,{content_type=content_type,filename=filename})
  end)
end
function M.stop_keepalive()
  if timer then timer:stop(); timer:close(); timer=nil end
end
function M.start_keepalive()
  M.stop_keepalive()
  local delay=require('brightspace.config').get().keepalive*1000
  if delay<=0 then return end
  local token=generation
  timer=vim.uv.new_timer()
  timer:start(delay,delay,main(function()
    if token==generation and timer then M.get_json('/d2l/api/lp/1.0/users/whoami',function() end) end
  end))
end
function M.logout(cb)
  if vim.in_fast_event() then return vim.schedule(function() M.logout(cb) end) end
  M.stop_keepalive()
  generation=generation+1
  if login.cancel then login.cancel() end
  authenticated, memory=false,nil
  local callbacks=flight; flight=nil
  if callbacks then for _,done in ipairs(callbacks) do done('logged_out') end end
  http.cancel_all(main(function()
  vim.uv.fs_unlink(require('brightspace.paths').cookie_jar())
  if keyring.available() then keyring.clear(main(function(err) (cb or function() end)(err and 'keyring_error' or nil) end))
  elseif cb then cb(nil) end
  end))
end
return M
