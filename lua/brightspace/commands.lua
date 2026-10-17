local M = {}
local state = require('brightspace.state').new()
local refresh_timer
local function stop()
  if refresh_timer then refresh_timer:stop(); refresh_timer:close(); refresh_timer=nil end
  require('brightspace.auth.session').stop_keepalive()
  require('brightspace.refresh').cancel(state)
end
local function update() require('brightspace.ui.workspace').update(state) end
local function refresh(force) require('brightspace.refresh').run(state,update,{force=force}) end
local function start()
  require('brightspace.auth.session').start_keepalive()
  if refresh_timer then return end
  local delay=math.max(1,require('brightspace.config').get().cache_ttl)*1000
  refresh_timer=vim.uv.new_timer()
  refresh_timer:start(delay,delay,vim.schedule_wrap(function()
    if require('brightspace.ui.workspace').is_open() then refresh(false) end
  end))
end
function M.run(sub)
  sub=vim.trim(sub or '')
  if sub=='' or sub=='open' then
    local workspace=require('brightspace.ui.workspace')
    if not workspace.is_open() then require('brightspace.refresh').load_cached(state) end
    workspace.open(state,{
      refresh=function() refresh(true) end,
      search=function() require('brightspace.search').open(state) end,
      select_course=function(id) require('brightspace.refresh').select(state,id,update) end,
      close=stop,
    })
    if not require('brightspace.auth.keyring').available() then
      vim.notify('Install libsecret-tools (secret-tool) for credential storage',vim.log.levels.WARN)
    end
    start()
    refresh(false)
  elseif sub=='refresh' then
    if require('brightspace.ui.workspace').is_open() then refresh(true) else M.run('open') end
  elseif sub=='search' then
    if #state.courses==0 then require('brightspace.refresh').load_cached(state) end
    require('brightspace.search').open(state)
  elseif sub=='logout' then
    local workspace=require('brightspace.ui.workspace')
    if workspace.is_open() then workspace.close() end
    if refresh_timer then refresh_timer:stop(); refresh_timer:close(); refresh_timer=nil end
    require('brightspace.refresh').cancel(state)
    require('brightspace.auth.session').logout(function(err)
      require('brightspace.store').clear_cache()
      state=require('brightspace.state').new()
      vim.notify(err and 'Brightspace: '..err or 'Brightspace: logged out',err and vim.log.levels.WARN or vim.log.levels.INFO)
    end)
  else
    vim.notify('Brightspace: unknown command. Use open, refresh, search, or logout.',vim.log.levels.ERROR)
  end
end
return M
