local M = {}
local time = require('brightspace.time')
function M.from_toc(course_id, toc)
  local function children(container)
    local raw, result = {}, {}
    for _, m in ipairs(container.Modules or {}) do raw[#raw+1] = {value=m,kind='module'} end
    for _, t in ipairs(container.Topics or {}) do raw[#raw+1] = {value=t,kind='topic'} end
    for i, entry in ipairs(raw) do entry.order = i end
    table.sort(raw, function(a,b)
      local x,y = tonumber(a.value.SortOrder) or a.order, tonumber(b.value.SortOrder) or b.order
      return x == y and a.order < b.order or x < y
    end)
    for _, entry in ipairs(raw) do
      local v, kind = entry.value, entry.kind
      if not v.IsHidden then
        local id = v.ModuleId or v.TopicId or v.Id
        local file_type = v.TypeIdentifier
        if type(file_type) ~= 'string' then file_type = v.TopicType == 1 and 'File' or 'Link' end
        local item = {key=kind..':'..course_id..':'..tostring(id),kind=kind,course_id=course_id,
          title=v.Title or 'Untitled', modified=time.parse(v.LastModifiedDate or v.LastModified),
          url=type(v.Url)=='string' and v.Url or nil,topic_id=kind=='topic' and id or nil,file_type=file_type}
        if kind == 'module' then item.children = children(v) end
        result[#result+1] = item
      end
    end
    return result
  end
  return children(toc or {})
end
function M.flatten(tree)
  local result = {}
  local function visit(items)
    for _, item in ipairs(items or {}) do
      result[#result+1] = item
      if item.children then visit(item.children) end
    end
  end
  visit(tree)
  return result
end
return M
