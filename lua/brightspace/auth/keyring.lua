local M = {}

local SERVICE = "brightspace.nvim"
local FIELDS = { "netid", "password" }

local runner

--- Default runner: run `cmd` with optional stdin; cb(code, stdout, stderr).
--- Callback runs in a luv fast context.
local function default_run(cmd, stdin, cb)
  vim.system(cmd, { stdin = stdin, text = true }, function(o)
    cb(o.code, o.stdout or "", o.stderr or "")
  end)
end

--- Inject a runner (tests). Pass nil to restore the default.
---@param fn function|nil
function M.set_runner(fn)
  runner = fn
end

local function run(cmd, stdin, cb)
  return (runner or default_run)(cmd, stdin, cb)
end

---@return boolean
function M.available()
  return vim.fn.executable("secret-tool") == 1
end

--- Collect a list of per-field operations sequentially; stops at first error.
local function each_field(op, cb)
  local i = 0
  local function step()
    i = i + 1
    if i > #FIELDS then
      return cb(nil)
    end
    op(FIELDS[i], function(err)
      if err then
        return cb(err)
      end
      step()
    end)
  end
  step()
end

---@param netid string
---@param password string
---@param cb fun(err:string|nil)
function M.store(netid, password, cb)
  local values = { netid = netid, password = password }
  each_field(function(field, done)
    run({
      "secret-tool", "store", "--label=" .. SERVICE .. " " .. field,
      "service", SERVICE, "field", field,
    }, values[field], function(code, _, stderr)
      done(code ~= 0 and ("secret-tool store failed: " .. (stderr or "")) or nil)
    end)
  end, cb)
end

---@param cb fun(err:string|nil, creds:{netid:string,password:string}|nil)
function M.get(cb)
  local creds = {}
  local missing = false
  each_field(function(field, done)
    run({ "secret-tool", "lookup", "service", SERVICE, "field", field }, nil, function(code, stdout, stderr)
      if code == 1 and (stderr or "") == "" then
        missing = true
        return done(nil)
      elseif code ~= 0 then
        return done("secret-tool lookup failed: " .. (stderr or ""))
      end
      creds[field] = stdout
      done(nil)
    end)
  end, function(err)
    if err then
      return cb(err, nil)
    end
    if missing or creds.netid == "" or creds.password == "" then
      return cb(nil, nil)
    end
    cb(nil, creds)
  end)
end

---@param cb fun(err:string|nil)
function M.clear(cb)
  each_field(function(field, done)
    run({ "secret-tool", "clear", "service", SERVICE, "field", field }, nil, function(code, _, stderr)
      -- exit 1 means nothing to clear
      done((code ~= 0 and not (code == 1 and (stderr or "") == "")) and ("secret-tool clear failed: " .. (stderr or "")) or nil)
    end)
  end, cb)
end

return M
