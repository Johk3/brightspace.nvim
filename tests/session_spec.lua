local http = require('brightspace.http')
local login = require('brightspace.auth.login')
local keyring = require('brightspace.auth.keyring')
describe('session', function()
  local s, originals, old_state, tmp, old_input, old_secret, old_store, old_notify
  before_each(function()
    old_state=vim.env.BRIGHTSPACE_STATE_DIR; tmp=vim.fn.tempname(); vim.env.BRIGHTSPACE_STATE_DIR=tmp
    old_input,old_secret,old_store,old_notify=vim.ui.input,vim.fn.inputsecret,keyring.store,vim.notify
    originals = {login.run, keyring.get, keyring.available, keyring.clear}
    package.loaded['brightspace.auth.session'] = nil
    s = require('brightspace.auth.session')
    keyring.available = function() return true end
    keyring.get = function(cb) cb(nil, {netid='example', password='synthetic'}) end
    keyring.clear = function(cb) cb(nil) end
  end)
  after_each(function()
    s.stop_keepalive()
    vim.ui.input,vim.fn.inputsecret,keyring.store,vim.notify=old_input,old_secret,old_store,old_notify
    vim.env.BRIGHTSPACE_STATE_DIR=old_state; vim.fn.delete(tmp,"rf")
    login.run, keyring.get, keyring.available, keyring.clear = unpack(originals)
    http.set_transport(nil)
  end)
  it('retries once after expiry', function()
    local gets, logins, done = 0, 0, false
    login.run = function(_, cb) logins=logins+1; cb(nil) end
    http.set_transport(function(_, cb)
      gets=gets+1
      cb(nil, gets==1 and {status=302, location='/d2l/login?a=b'} or {status=200, body='{"ok":true}'})
    end)
    s.get_json('/test', function(err, data) assert.is_nil(err); assert.is_true(data.ok); done=true end)
    vim.wait(1000,function() return done end)
    assert.is_true(done); assert.equals(1,logins); assert.equals(2,gets)
  end)
  it('serializes concurrent expired requests', function()
    local pending, logins, completed = nil, 0, 0
    login.run = function(_, cb) logins=logins+1; pending=cb end
    http.set_transport(function(_, cb) cb(nil, pending and {status=401} or {status=200,body='{}'}) end)
    -- Both requests fail before the shared login completes.
    http.set_transport(function(_, cb) cb(nil, completed==0 and {status=401} or {status=200,body='{}'}) end)
    s.get_json('/a', function() completed=completed+1 end)
    s.get_json('/b', function() completed=completed+1 end)
    assert.equals(1,logins)
    http.set_transport(function(_, cb) cb(nil,{status=200,body='{}'}) end)
    pending(nil)
    assert.equals(2,completed)
  end)
  it('invalidates authentication on logout', function()
    local pending, result
    login.run=function(_, cb) pending=cb end
    s.ensure(function(err) result=err end)
    s.logout(function() end)
    pending(nil)
    assert.equals('logged_out',result)
  end)
  it('reprompts once after rejected credentials and stops', function()
    local prompts,logins,result=0,0,nil
    vim.notify=function() end
    vim.ui.input=function(_,cb) prompts=prompts+1; cb('example') end
    vim.fn.inputsecret=function() return 'synthetic' end
    keyring.store=function(_,_,cb) cb(nil) end
    login.run=function(_,cb) logins=logins+1; cb('bad_credentials') end
    s.ensure(function(err) result=err end)
    assert.equals('bad_credentials',result)
    assert.equals(1,prompts); assert.equals(2,logins)
  end)
  it('stops after one retry when session stays expired', function()
    local gets,logins,result=0,0,nil
    login.run=function(_,cb) logins=logins+1; cb(nil) end
    http.set_transport(function(_,cb) gets=gets+1; cb(nil,{status=403}) end)
    s.get_json('/test',function(err) result=err end)
    assert.equals('session_expired',result)
    assert.equals(2,gets); assert.equals(1,logins)
  end)
  it('reuses an existing valid cookie session without keyring', function()
    vim.fn.writefile({'synthetic'},require('brightspace.paths').cookie_jar())
    keyring.get=function() error('must reuse cookie session') end
    http.set_transport(function(_,cb) cb(nil,{status=200,body='{}'}) end)
    local done=false
    s.ensure(function(err) assert.is_nil(err); done=true end)
    assert.is_true(done)
  end)
  it('schedules callbacks from transport fast events', function()
    local done=false
    http.set_transport(function(_,cb)
      local timer=vim.uv.new_timer()
      timer:start(0,0,function() timer:close(); cb(nil,{status=200,body='{}'}) end)
    end)
    s.get_json('/test',function(err,data)
      assert.is_false(vim.in_fast_event()); assert.is_nil(err); assert.is_table(data); done=true
    end)
    vim.wait(1000,function() return done end)
    assert.is_true(done)
  end)
  it('refuses off-origin requests', function()
    local called=false
    http.set_transport(function() called=true end)
    s.get_json('https://evil.test/path',function(err) assert.equals('invalid_path',err) end)
    assert.is_false(called)
  end)
  it('follows same-origin file redirects without following off-origin ones', function()
    local calls, result=0,nil
    http.set_transport(function(req,cb)
      calls=calls+1
      if calls==1 then return cb(nil,{status=302,location='/files/example.pdf'}) end
      assert.equals('https://brightspace.tudelft.nl/files/example.pdf',req.url)
      cb(nil,{status=200,headers={['content-type']='application/pdf'}})
    end)
    s.download('/file',vim.fn.tempname(),function(err) result=err or 'ok' end)
    assert.equals('ok',result); assert.equals(2,calls)
    calls=0
    http.set_transport(function(_,cb) calls=calls+1; cb(nil,{status=302,location='https://evil.test/file'}) end)
    s.download('/file',vim.fn.tempname(),function(err) result=err end)
    assert.equals('invalid_path',result); assert.equals(1,calls)
  end)
  it('reads authenticated HTML content and rejects login forms', function()
    local body='<html><h1>Example lesson</h1></html>'
    http.set_transport(function(_,cb) cb(nil,{status=200,headers={['content-type']='text/html'},body=body}) end)
    local result
    s.html('/topic',function(err,html) assert.is_nil(err); result=html end)
    assert.equals(body,result)
    body='<form action="/login"><input type="password" name="password"></form>'
    s.html('/topic',function(err,html) assert.equals('session_expired',err); assert.is_nil(html) end)
  end)
  it('rejects HTML responses that redirect to login', function()
    http.set_transport(function(_,cb)
      cb(nil,{status=200,headers={['content-type']='text/html'},body='<script>window.location.href="/d2l/login";</script>'})
    end)
    local result
    s.html('/topic',function(err) result=err end)
    assert.equals('session_expired',result)
  end)
  it('rejects meta-refresh redirects to login', function()
    http.set_transport(function(_,cb)
      cb(nil,{status=200,headers={['content-type']='text/html'},body='<meta http-equiv="refresh" content="0;url=/d2l/login">'})
    end)
    local result
    s.html('/topic',function(err) result=err end)
    assert.equals('session_expired',result)
  end)
  it('rejects binary responses from the HTML interface', function()
    http.set_transport(function(_,cb) cb(nil,{status=200,headers={['content-type']='application/pdf'},body='%PDF'}) end)
    s.html('/topic',function(err) assert.equals('bad_response',err) end)
  end)
  it('refuses html download and removes destination', function()
    local dest=vim.fn.tempname()
    vim.fn.writefile({'html'},dest)
    http.set_transport(function(_,cb) cb(nil,{status=200,headers={['content-type']='text/html; charset=utf-8'}}) end)
    s.download('/file',dest,function(err) assert.equals('not_a_file',err) end)
    assert.is_nil(vim.uv.fs_stat(dest))
  end)
end)
