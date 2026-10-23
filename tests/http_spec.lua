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

describe("http.request against loopback server", function()
  local server, port, log, saved, root

  local function respond(sock, status, extra, body)
    sock:write(("HTTP/1.1 %s\r\n%sContent-Length: %d\r\nConnection: close\r\n\r\n%s"):format(status, extra, #body, body))
    sock:shutdown(function()
      sock:close()
    end)
  end

  before_each(function()
    saved = vim.env.BRIGHTSPACE_STATE_DIR
    root = vim.fn.tempname()
    vim.env.BRIGHTSPACE_STATE_DIR = root
    log = {}
    server = vim.uv.new_tcp()
    server:bind("127.0.0.1", 0)
    port = server:getsockname().port
    server:listen(8, function()
      local sock = vim.uv.new_tcp()
      server:accept(sock)
      local buf = ""
      sock:read_start(function(err, chunk)
        if err or not chunk then
          return
        end
        buf = buf .. chunk
        local head, rest = buf:match("^(.-)\r\n\r\n(.*)$")
        if not head then
          return
        end
        local len = tonumber(head:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")) or 0
        if #rest < len then
          return
        end
        sock:read_stop()
        local method, path = head:match("^(%S+)%s+(%S+)")
        table.insert(log, { method = method, path = path, body = rest })
        if path == "/get" then
          respond(sock, "200 OK", "X-Test: yes\r\n", "hello")
        elseif path == "/post" then
          respond(sock, "200 OK", "", "posted")
        elseif path == "/redir" then
          respond(sock, "302 Found", "Location: /dest\r\n", "")
        else
          respond(sock, "200 OK", "", "dest")
        end
      end)
    end)
  end)

  after_each(function()
    server:close()
    vim.env.BRIGHTSPACE_STATE_DIR = saved
    vim.fn.delete(root, "rf")
  end)

  local function url(p)
    return ("http://127.0.0.1:%d%s"):format(port, p)
  end

  local function call(req)
    local done, err, res
    http.request(req, function(e, r)
      done, err, res = true, e, r
    end)
    vim.wait(10000, function()
      return done
    end)
    return err, res
  end

  it("downloads to a file without a fixed deadline", function()
    local argv
    local system = vim.system
    vim.system = function(cmd, ...) argv = cmd; return system(cmd, ...) end
    local dest = root .. "/download"
    vim.fn.mkdir(root, "p")
    local err, res = call({ url = url("/get"), output = dest })
    vim.system = system
    assert.is_nil(err)
    assert.equals(200, res.status)
    assert.same({ "hello" }, vim.fn.readfile(dest))
    assert.is_nil(vim.tbl_contains(argv, "--max-time") or nil)
    assert.is_true(vim.tbl_contains(argv, "--speed-time"))
  end)

  it("GET parses status, headers and body", function()
    local err, res = call({ url = url("/get") })
    assert.is_nil(err)
    assert.equals(200, res.status)
    assert.equals("hello", res.body)
    assert.equals("yes", res.headers["x-test"])
  end)

  it("POST sends the form body", function()
    local err, res = call({ method = "POST", url = url("/post"), form = { b = "x y", a = "1" } })
    assert.is_nil(err)
    assert.equals("posted", res.body)
    assert.equals("POST", log[1].method)
    assert.equals("a=1&b=x+y", log[1].body)
  end)

  it("POST with follow turns the redirect into a GET", function()
    local err, res = call({ method = "POST", url = url("/redir"), form = { a = "1" }, follow = true })
    assert.is_nil(err)
    assert.equals(200, res.status)
    assert.equals("dest", res.body)
    assert.equals("GET", log[#log].method)
    assert.equals("/dest", log[#log].path)
    assert.equals(url("/dest"), res.url)
  end)

  it("allows chaining a request from inside a callback", function()
    local done, second
    http.request({ url = url("/get") }, function()
      http.request({ url = url("/dest") }, function(e, r)
        second = { e, r }
        done = true
      end)
    end)
    vim.wait(10000, function()
      return done
    end)
    assert.is_true(done)
    assert.is_nil(second[1])
    assert.equals("dest", second[2].body)
  end)
end)
