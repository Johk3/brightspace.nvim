local M = {}

local named = { amp = "&", quot = '"', apos = "'", lt = "<", gt = ">", nbsp = " " }

local function decode(s)
  return (s:gsub("&(#?[%w]+);", function(e)
    if e:sub(1, 2):lower() == "#x" then
      local n = tonumber(e:sub(3), 16)
      return n and vim.fn.nr2char(n) or nil
    elseif e:sub(1, 1) == "#" then
      local n = tonumber(e:sub(2))
      return n and vim.fn.nr2char(n) or nil
    end
    return named[e]
  end))
end

local function attrs(tag)
  local out = {}
  for name, _, value in tag:gmatch("([%w_:-]+)%s*=%s*([\"'])(.-)%2") do
    out[name:lower()] = decode(value)
  end
  return out
end

local function resolve(action, base)
  if action == "" then
    return base
  end
  if action:match("^%a[%w+.-]*:") then
    return action
  end
  local origin = base:match("^(%a[%w+.-]*://[^/?#]*)")
  if not origin then
    return action
  end
  if action:sub(1, 2) == "//" then
    return origin:match("^(%a[%w+.-]*:)") .. action
  end
  if action:sub(1, 1) == "/" then
    return origin .. action
  end
  if action:sub(1, 1) == "?" then
    return (base:gsub("[?#].*$", "")) .. action
  end
  local dir = base:gsub("[?#].*$", ""):sub(#origin + 1):match("^(.*/)") or "/"
  return origin .. dir .. action
end

---@param html string
---@param base_url string
---@return table[]
function M.parse(html, base_url)
  local forms = {}
  local pos = 1
  while true do
    local s, e, open = html:find("<[Ff][Oo][Rr][Mm](%s[^>]*)>", pos)
    if not s then
      s, e, open = html:find("<[Ff][Oo][Rr][Mm]()>", pos)
      if not s then
        break
      end
      open = ""
    end
    local cs, ce = html:lower():find("</form%s*>", e + 1)
    local body = html:sub(e + 1, (cs or #html + 1) - 1)
    local a = attrs(open)
    local form = {
      id = a.id,
      action = resolve(a.action or "", base_url),
      method = (a.method or "GET"):upper(),
      inputs = {},
    }
    for tag in body:gmatch("<[Ii][Nn][Pp][Uu][Tt]%s[^>]*>") do
      local ia = attrs(tag)
      if ia.name then
        form.inputs[ia.name] = ia.value or ""
      end
    end
    forms[#forms + 1] = form
    pos = (ce or #html) + 1
  end
  return forms
end

---@param list table[]
---@param pred fun(form: table): boolean
function M.find(list, pred)
  for _, f in ipairs(list) do
    if pred(f) then
      return f
    end
  end
  return nil
end

return M
