local http = require("brightspace.http")
local paths = require("brightspace.paths")

describe("http encoding", function()
  it("encodes forms deterministically", function()
    assert.equals("a=p%26w%3D1&b=x+y", http.encode_form({ b = "x y", a = "p&w=1" }))
  end)

  it("urlencodes reserved characters", function()
    assert.equals("a%2Fb%20c-_.~", http.urlencode("a/b c-_.~"))
  end)
end)

describe("http._parse_headers", function()
  it("uses the last header block", function()
    local raw = "HTTP/2 302 \r\nLocation: /a\r\nSet-Cookie: x\r\n\r\nHTTP/2 200 \r\nContent-Type: text/html\r\n\r\n"
    local status, headers, location = http._parse_headers(raw)
    assert.equals(200, status)
    assert.equals("text/html", headers["content-type"])
    assert.is_nil(headers["set-cookie"])
    assert.is_nil(location)
  end)

  it("exposes location", function()
    local status, _, location = http._parse_headers("HTTP/1.1 302 Found\r\nLocation: /next\r\n\r\n")
    assert.equals(302, status)
    assert.equals("/next", location)
  end)
end)

describe("http.set_transport", function()
  it("routes requests through the injected transport", function()
    local seen
    http.set_transport(function(req, cb)
      seen = req
      cb(nil, { status = 204, headers = {}, body = "", url = req.url })
    end)
    local got
    http.request({ url = "https://x.test/" }, function(err, res)
      got = { err, res }
    end)
    http.set_transport(nil)
    assert.equals("https://x.test/", seen.url)
    assert.is_nil(got[1])
    assert.equals(204, got[2].status)
  end)
end)

describe("paths", function()
  local saved = {}
  local names = { "BRIGHTSPACE_STATE_DIR", "BRIGHTSPACE_CACHE_DIR", "BRIGHTSPACE_DATA_DIR" }
  before_each(function()
    for _, n in ipairs(names) do
      saved[n] = vim.env[n]
    end
  end)
  after_each(function()
    for _, n in ipairs(names) do
      vim.env[n] = saved[n]
    end
  end)

  it("honors env overrides and creates dirs", function()
    local root = vim.fn.tempname()
    vim.env.BRIGHTSPACE_STATE_DIR = root .. "/s"
    vim.env.BRIGHTSPACE_CACHE_DIR = root .. "/c"
    vim.env.BRIGHTSPACE_DATA_DIR = root .. "/d"
    assert.equals(root .. "/s", paths.state())
    assert.equals(root .. "/c", paths.cache())
    assert.equals(root .. "/d", paths.data())
    assert.equals(1, vim.fn.isdirectory(root .. "/s"))
    assert.equals(root .. "/s/cookies.txt", paths.cookie_jar())
    vim.fn.delete(root, "rf")
  end)

  it("defaults under stdpath", function()
    vim.env.BRIGHTSPACE_STATE_DIR = nil
    assert.equals(vim.fn.stdpath("state") .. "/brightspace", paths.state())
  end)
end)

describe("http.request (curl)", function()
  it("fails cleanly when curl cannot connect", function()
    local root = vim.fn.tempname()
    vim.env.BRIGHTSPACE_STATE_DIR = root
    local done, err, res
    http.request({ url = "http://127.0.0.1:1/" }, function(e, r)
      done, err, res = true, e, r
    end)
    vim.wait(10000, function()
      return done
    end)
    vim.env.BRIGHTSPACE_STATE_DIR = nil
    vim.fn.delete(root, "rf")
    assert.is_true(done)
    assert.is_string(err)
    assert.is_nil(res)
  end)
end)
