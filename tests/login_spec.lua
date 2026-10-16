local http = require("brightspace.http")
local login = require("brightspace.auth.login")

local function fixture(name)
  local f = assert(io.open("tests/fixtures/login/" .. name .. ".html", "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local BS = "https://brightspace.tudelft.nl"
local IDP = "https://login.tudelft.nl/idp/login.php"
local ENGINE = "https://engine.surfconext.nl/authentication/sp/consume-assertion"
local SAML_LOGIN = BS .. "/d2l/lp/auth/login/samlLogin.d2l"
local WHOAMI = BS .. "/d2l/api/lp/1.0/users/whoami"

local function page(url, name, status)
  return { status = status or 200, headers = {}, body = fixture(name), url = url }
end

describe("login.run", function()
  local saved_state
  local tmp
  local calls

  local function use(routes)
    calls = {}
    http.set_transport(function(req, cb)
      local key = (req.method or "GET") .. " " .. req.url:gsub("%?.*$", "")
      calls[#calls + 1] = { key = key, req = req }
      local r = routes[key]
      if type(r) == "function" then
        r = r(req)
      end
      if not r then
        return cb(nil, { status = 404, headers = {}, body = "", url = req.url })
      end
      cb(nil, r)
    end)
  end

  local function count(key)
    local n = 0
    for _, c in ipairs(calls) do
      if c.key == key then
        n = n + 1
      end
    end
    return n
  end

  local function run(creds)
    local done, err, called = false, nil, 0
    login.run(creds or { netid = "jdoe", password = "hunter2" }, function(e)
      called = called + 1
      err, done = e, true
    end)
    vim.wait(2000, function()
      return done
    end)
    return err, called
  end

  before_each(function()
    saved_state = vim.env.BRIGHTSPACE_STATE_DIR
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    vim.env.BRIGHTSPACE_STATE_DIR = tmp
  end)

  after_each(function()
    http.set_transport(nil)
    vim.env.BRIGHTSPACE_STATE_DIR = saved_state
    vim.fn.delete(tmp, "rf")
  end)

  it("logs in through idp and surfconext", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(IDP .. "?AuthState=abc", "idp_login"),
      ["POST " .. IDP] = page(IDP, "saml_to_surfconext"),
      ["POST " .. ENGINE] = page(ENGINE, "saml_to_brightspace"),
      ["POST " .. SAML_LOGIN] = page(BS .. "/d2l/home", "home"),
      ["GET " .. WHOAMI] = { status = 200, headers = {}, body = '{"Identifier":"1"}', url = WHOAMI },
    })
    local err, called = run()
    assert.is_nil(err)
    assert.equals(1, called)
    local post
    for _, c in ipairs(calls) do
      if c.key == "POST " .. IDP then
        post = c.req
      end
    end
    assert.equals("jdoe", post.form.username)
    assert.equals("hunter2", post.form.password)
    assert.equals("fake-state", post.form.AuthState)
    assert.equals("https://login.tudelft.nl/idp/login.php?AuthState=abc", post.url)
    assert.equals(1, count("GET " .. WHOAMI))
  end)

  it("relays saml fields to each form action", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(IDP, "idp_login"),
      ["POST " .. IDP] = page(IDP, "saml_to_surfconext"),
      ["POST " .. ENGINE] = page(ENGINE, "saml_to_brightspace"),
      ["POST " .. SAML_LOGIN] = page(BS .. "/d2l/home", "home"),
      ["GET " .. WHOAMI] = { status = 200, headers = {}, body = "{}", url = WHOAMI },
    })
    assert.is_nil((run()))
    for _, c in ipairs(calls) do
      if c.key == "POST " .. ENGINE then
        assert.equals("ZmFrZS1yZXNwb25zZS0x", c.req.form.SAMLResponse)
        assert.equals("fake-relay", c.req.form.RelayState)
      elseif c.key == "POST " .. SAML_LOGIN then
        assert.equals(SAML_LOGIN, c.req.url)
        assert.equals("ZmFrZS1yZXNwb25zZS0y", c.req.form.SAMLResponse)
        assert.equals("fake-relay", c.req.form.RelayState)
      end
    end
  end)

  it("submits GET forms via the query string", function()
    local html = '<form method="get" action="https://login.tudelft.nl/go?a=1"><input name="SAMLRequest" value="x y"></form>'
    use({
      ["GET " .. BS .. "/d2l/login"] = { status = 200, headers = {}, body = html, url = IDP },
      ["GET https://login.tudelft.nl/go"] = page(BS .. "/d2l/home", "home"),
      ["GET " .. WHOAMI] = { status = 200, headers = {}, body = "{}", url = WHOAMI },
    })
    assert.is_nil((run()))
    assert.equals("https://login.tudelft.nl/go?a=1&SAMLRequest=x+y", calls[2].req.url)
    assert.is_nil(calls[2].req.form)
  end)

  it("reports a transport error on the first request once", function()
    http.set_transport(function(req, cb)
      cb("could not resolve host", nil)
    end)
    local err, called = run()
    assert.equals("unexpected: could not resolve host", err)
    assert.equals(1, called)
  end)

  it("is callable from a fast context", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(BS .. "/d2l/home", "home"),
      ["GET " .. WHOAMI] = { status = 200, headers = {}, body = "{}", url = WHOAMI },
    })
    local done, err, ok = false, nil, nil
    local timer = vim.uv.new_timer()
    timer:start(0, 0, function()
      ok = pcall(login.run, { netid = "jdoe", password = "hunter2" }, function(e)
        err, done = e, true
      end)
      timer:close()
    end)
    vim.wait(2000, function()
      return done
    end)
    assert.is_true(ok)
    assert.is_true(done)
    assert.is_nil(err)
  end)

  it("rejects bad credentials", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(IDP, "idp_login"),
      ["POST " .. IDP] = page(IDP, "idp_login"),
    })
    local err = run()
    assert.equals("bad_credentials", err)
    assert.equals(1, count("POST " .. IDP))
  end)

  it("reports consent_required", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(ENGINE, "consent"),
    })
    assert.equals("consent_required", (run()))
  end)

  it("fails when whoami is not json", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(BS .. "/d2l/home", "home"),
      ["GET " .. WHOAMI] = { status = 200, headers = {}, body = "<html>", url = WHOAMI },
    })
    local err = run()
    assert.is_truthy(err:find("^unexpected: "))
  end)

  it("reports unexpected pages without query or body", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = { status = 500, headers = {}, body = "secret body", url = "https://x.test/a/b?token=zzz" },
    })
    local err = run()
    assert.equals("unexpected: 500 x.test/a/b", err)
  end)

  it("stops after max hops", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(ENGINE, "saml_to_surfconext"),
      ["POST " .. ENGINE] = page(ENGINE, "saml_to_surfconext"),
    })
    local err, called = run()
    assert.equals("unexpected: too many steps", err)
    assert.equals(1, called)
    assert.equals(15, #calls)
  end)

  it("error message never contains password", function()
    use({
      ["GET " .. BS .. "/d2l/login"] = page(IDP, "idp_login"),
      ["POST " .. IDP] = function(req)
        return nil
      end,
    })
    local err = run()
    assert.is_truthy(err)
    assert.is_nil(err:find("hunter2", 1, true))

    http.set_transport(function(req, cb)
      if req.form then
        return cb("curl failed for body " .. require("brightspace.http").encode_form(req.form), nil)
      end
      cb(nil, page(IDP, "idp_login"))
    end)
    err = run()
    assert.is_truthy(err:find("^unexpected: "))
    assert.is_nil(err:find("hunter2", 1, true))
  end)

  it("wipes the cookie jar first", function()
    local jar = require("brightspace.paths").cookie_jar()
    local f = io.open(jar, "w")
    f:write("stale")
    f:close()
    use({})
    run()
    assert.is_nil(vim.uv.fs_stat(jar))
  end)
end)
