local M = {}

local transport

--- Replace the transport (used by tests). Pass nil to restore curl.
---@param fn function|nil
function M.set_transport(fn)
  transport = fn
end

---@param s string
---@return string
function M.urlencode(s)
  return (tostring(s):gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end

--- Urlencode a form table with sorted keys; spaces become '+'.
---@param tbl table<string,string>
---@return string
function M.encode_form(tbl)
  local keys = vim.tbl_keys(tbl)
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = M.urlencode(k):gsub("%%20", "+") .. "=" .. M.urlencode(tbl[k]):gsub("%%20", "+")
  end
  return table.concat(parts, "&")
end

--- Parse a curl header dump, keeping only the last response block.
---@param raw string
---@return integer status, table<string,string> headers, string|nil location
function M._parse_headers(raw)
  local blocks = {}
  for block in (raw:gsub("\r\n", "\n") .. "\n\n"):gmatch("(.-)\n\n") do
    if block:match("%S") then
      blocks[#blocks + 1] = block
    end
  end
  local last = blocks[#blocks] or ""
  local status = 0
  local headers = {}
  local first = true
  for line in last:gmatch("[^\n]+") do
    if first then
      status = tonumber(line:match("^HTTP/%S+%s+(%d+)")) or 0
      first = false
    else
      local name, value = line:match("^([^:]+):%s*(.-)%s*$")
      if name then
        headers[name:lower()] = value
      end
    end
  end
  return status, headers, headers["location"]
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return ""
  end
  local data = f:read("*a")
  f:close()
  return data
end

local function ensure_jar(jar)
  local fd = vim.uv.fs_open(jar, "a", 384)
  if fd then
    vim.uv.fs_close(fd)
  end
  vim.uv.fs_chmod(jar, 384)
end

local curl_request
function curl_request(req, cb)
  if vim.in_fast_event() then
    return vim.schedule(function()
      curl_request(req, cb)
    end)
  end
  local jar = require("brightspace.paths").cookie_jar()
  ensure_jar(jar)
  local hdr_file = vim.fn.tempname()
  local cmd = {
    "curl", "-sS", "--compressed", "--connect-timeout", "15",
    "-b", jar, "-c", jar, "-D", hdr_file,
    "-w", "\n%{url_effective}",
  }
  -- GET is curl's default and a POST body implies POST; forcing -X would be
  -- kept across redirects and break POST->302->GET.
  local method = req.method or "GET"
  if method ~= "GET" and not (method == "POST" and req.form) then
    vim.list_extend(cmd, { "-X", method })
  end
  if req.follow then
    cmd[#cmd + 1] = "-L"
  end
  if req.output then
    vim.list_extend(cmd, { "-o", req.output })
  end
  for k, v in pairs(req.headers or {}) do
    vim.list_extend(cmd, { "-H", k .. ": " .. v })
  end
  local stdin
  if req.form then
    stdin = M.encode_form(req.form)
    vim.list_extend(cmd, {
      "-H", "Content-Type: application/x-www-form-urlencoded",
      "--data-binary", "@-",
    })
  end
  vim.list_extend(cmd, { "--", req.url })

  local ok, spawn_err = pcall(vim.system, cmd, { stdin = stdin, text = false }, function(out)
    local raw = read_file(hdr_file)
    vim.uv.fs_unlink(hdr_file)
    vim.uv.fs_chmod(jar, 384)
    if out.code ~= 0 then
      local msg = out.stderr and #out.stderr > 0 and out.stderr or ("curl exited with " .. out.code)
      return cb((msg:gsub("%s+$", "")), nil)
    end
    local stdout = out.stdout or ""
    local nl = stdout:find("\n[^\n]*$")
    local body, url = stdout, req.url
    if nl then
      body, url = stdout:sub(1, nl - 1), stdout:sub(nl + 1)
    end
    local status, headers, location = M._parse_headers(raw)
    cb(nil, { status = status, headers = headers, location = location, body = body, url = url })
  end)
  if not ok then
    vim.uv.fs_unlink(hdr_file)
    cb("failed to run curl: " .. tostring(spawn_err), nil)
  end
end

--- Perform an HTTP request. Default transport is curl with a shared cookie jar.
--- Form bodies go over stdin so secrets never reach argv.
--- With the curl transport `cb` runs in a luv fast context (no vim.fn / vim.api);
--- callers must vim.schedule if they need those. request() itself may be called
--- from any context, including from another request's callback.
---@param req {method:string|nil, url:string, form:table|nil, follow:boolean|nil, output:string|nil, headers:table|nil}
---@param cb fun(err:string|nil, res:table|nil)
function M.request(req, cb)
  if transport then
    return transport(req, cb)
  end
  return curl_request(req, cb)
end

return M
