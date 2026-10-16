local keyring = require("brightspace.auth.keyring")

describe("keyring", function()
  local calls
  local function fake(responses)
    calls = {}
    keyring.set_runner(function(cmd, stdin, cb)
      table.insert(calls, { cmd = cmd, stdin = stdin })
      local r = responses(cmd, stdin) or { 0, "", "" }
      cb(r[1], r[2], r[3])
    end)
  end
  after_each(function()
    keyring.set_runner(nil)
  end)

  it("store passes the secret via stdin only", function()
    fake(function() end)
    local err = "unset"
    keyring.store("abc", "s3cret", function(e)
      err = e
    end)
    assert.is_nil(err)
    assert.equals(2, #calls)
    for _, c in ipairs(calls) do
      assert.equals("secret-tool", c.cmd[1])
      assert.equals("store", c.cmd[2])
      assert.is_nil(table.concat(c.cmd, " "):find("s3cret", 1, true))
    end
    assert.equals("abc", calls[1].stdin)
    assert.equals("s3cret", calls[2].stdin)
    assert.same(
      { "secret-tool", "store", "--label=brightspace.nvim password", "service", "brightspace.nvim", "field", "password" },
      calls[2].cmd
    )
  end)

  it("get returns nil without error when nothing is stored", function()
    fake(function()
      return { 1, "", "" }
    end)
    local err, creds = "unset", "unset"
    keyring.get(function(e, c)
      err, creds = e, c
    end)
    assert.is_nil(err)
    assert.is_nil(creds)
  end)

  it("get returns both fields", function()
    fake(function(cmd)
      return { 0, cmd[#cmd] == "netid" and "abc" or "pw", "" }
    end)
    local creds
    keyring.get(function(_, c)
      creds = c
    end)
    assert.same({ netid = "abc", password = "pw" }, creds)
  end)

  it("get reports real failures", function()
    fake(function()
      return { 2, "", "boom" }
    end)
    local err
    keyring.get(function(e)
      err = e
    end)
    assert.is_string(err)
  end)

  it("clear removes both fields", function()
    fake(function() end)
    local err = "unset"
    keyring.clear(function(e)
      err = e
    end)
    assert.is_nil(err)
    assert.equals(2, #calls)
    assert.equals("clear", calls[1].cmd[2])
  end)
end)
