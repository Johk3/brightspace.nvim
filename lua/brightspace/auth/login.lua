local http = require("brightspace.http")
local forms = require("brightspace.auth.forms")

local M = {}

local MAX_HOPS = 15
local WHOAMI_PATH = "/d2l/api/lp/1.0/users/whoami"
local LOGIN_PATH = "/d2l/login"
local CONSENT_HOST = "engine.surfconext.nl"

local function host_of(url)
  return (url or ""):match("^%a[%w+.-]*://([^/?#]*)") or ""
end

local function path_of(url)
  local rest = (url or ""):gsub("^%a[%w+.-]*://[^/?#]*", "")
  return (rest:gsub("[?#].*$", ""))
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

--- Run the SAML login against Brightspace. `cb(err)` is called exactly once;
--- err is nil, "bad_credentials", "consent_required" or "unexpected: <detail>".
--- The callback may run in a luv fast context.
---@param creds {netid:string, password:string}
---@param cb fun(err:string|nil)
function M.run(creds, cb)
  local base = require("brightspace.config").get().base_url:gsub("/+$", "")
  local bs_host = host_of(base)
  local jar = require("brightspace.paths").cookie_jar()
  local secrets = { creds.password, creds.netid }

  local finished = false
  local hops = 0
  local submitted = false

  local function scrub(s)
    s = tostring(s)
    for _, secret in ipairs(secrets) do
      if secret and secret ~= "" then
        s = s:gsub(vim.pesc(secret), "***")
      end
    end
    return s
  end

  local function finish(err)
    if finished then
      return
    end
    finished = true
    cb(err)
  end

  local function fail_at(res)
    finish(("unexpected: %d %s%s"):format(res.status or 0, host_of(res.url), path_of(res.url)))
  end

  -- Every state-machine request counts toward the hop limit (whoami excluded).
  local function send(req, handler)
    if hops >= MAX_HOPS then
      return finish("unexpected: too many steps")
    end
    hops = hops + 1
    req.follow = true
    http.request(req, function(err, res)
      if err then
        return finish("unexpected: " .. scrub(err))
      end
      handler(res)
    end)
  end

  local function check_whoami()
    http.request({ method = "GET", url = base .. WHOAMI_PATH, follow = false }, function(err, res)
      if err then
        return finish("unexpected: " .. scrub(err))
      end
      if res.status == 200 and pcall(vim.json.decode, res.body or "") then
        return finish(nil)
      end
      finish(("unexpected: %d %s%s"):format(res.status or 0, bs_host, WHOAMI_PATH))
    end)
  end

  local step
  function step(res)
    local list = forms.parse(res.body or "", res.url)
    local pw = forms.find(list, function(f)
      return f.inputs.password ~= nil
    end)
    if pw then
      if submitted then
        return finish("bad_credentials")
      end
      submitted = true
      local form = copy(pw.inputs)
      form.username = creds.netid
      form.password = creds.password
      return send({ method = "POST", url = pw.action, form = form }, step)
    end
    local saml = forms.find(list, function(f)
      return f.inputs.SAMLResponse ~= nil or f.inputs.SAMLRequest ~= nil
    end)
    if saml then
      return send({ method = "POST", url = saml.action, form = copy(saml.inputs) }, step)
    end
    if host_of(res.url) == bs_host and res.status == 200 then
      return check_whoami()
    end
    if host_of(res.url) == CONSENT_HOST and #list > 0 then
      return finish("consent_required")
    end
    fail_at(res)
  end

  local function start()
    send({ method = "GET", url = base .. LOGIN_PATH }, step)
  end

  vim.uv.fs_unlink(jar, function()
    start()
  end)
end

return M
