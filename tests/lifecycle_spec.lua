describe('request cancellation',function()
  it('waits for killed curl before reporting cancellation complete',function()
    local http=require('brightspace.http')
    local old_system,old_state=vim.system,vim.env.BRIGHTSPACE_STATE_DIR
    local root=vim.fn.tempname(); vim.env.BRIGHTSPACE_STATE_DIR=root
    local callback,killed,finished,request_error
    vim.system=function(_,_,cb) callback=cb; return {kill=function() killed=true end} end
    local ok,err=pcall(function()
      http.request({url='https://example.org'},function(e) request_error=e end)
      http.cancel_all(function() finished=true end)
      assert.is_true(killed)
      assert.is_nil(finished)
      callback({code=143,stdout='',stderr=''})
      assert.is_true(finished)
      assert.equals('cancelled',request_error)
    end)
    vim.system=old_system; vim.env.BRIGHTSPACE_STATE_DIR=old_state; vim.fn.delete(root,'rf')
    assert.is_true(ok,err)
  end)
  it('clears keyring only after a pending store finishes',function()
    local keyring=require('brightspace.auth.keyring')
    local pending,events,finished
    events={}
    keyring.set_runner(function(cmd,_,cb)
      events[#events+1]=cmd[2]..':'..cmd[#cmd]
      if cmd[2]=='store' and not pending then pending=cb else cb(0,'','') end
    end)
    local ok,err=pcall(function()
      keyring.store('example','synthetic',function() end)
      keyring.clear(function() finished=true end)
      assert.is_nil(finished)
      pending(0,'','')
      assert.is_true(finished)
      assert.same({'store:netid','store:password','clear:netid','clear:password'},events)
    end)
    keyring.set_runner(nil)
    assert.is_true(ok,err)
  end)
end)
