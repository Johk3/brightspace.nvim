local M = {}
local time = require('brightspace.time')
local function text(value) return type(value) == 'string' and value or nil end
local function date(row)
  return time.parse(row.LastModifiedDate) or time.parse(row.StartDate) or time.parse(row.CreatedDate)
end
function M.from_api(course_id, raw)
  local result = {}
  for _, row in ipairs(raw or {}) do
    if not row.IsHidden and not row.IsDeleted then
      local body = type(row.Body)=='table' and row.Body or {}
      result[#result+1] = {key='news:'..course_id..':'..tostring(row.Id), kind='news',course_id=course_id,
        title=row.Title or 'Announcement',body_html=text(body.Html) or text(body.Text) or '',
        modified=date(row)}
    end
  end
  table.sort(result, function(a,b) return (a.modified or 0) > (b.modified or 0) end)
  return result
end
function M.overview(course_id, raw)
  raw = raw or {}
  local body = type(raw.Description)=='table' and raw.Description or (type(raw.Body)=='table' and raw.Body or raw)
  if type(body) == 'table' then body = text(body.Html) or text(body.Text) end
  if type(body) ~= 'string' or body == '' then return nil end
  return {key='info:'..course_id..':overview',kind='info',course_id=course_id,title='Course info',body_html=body,
    modified=time.parse(raw.LastModifiedDate) or vim.fn.sha256(body)}
end
return M
