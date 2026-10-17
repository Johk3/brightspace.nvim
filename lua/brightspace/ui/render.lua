local M = {}

local function clean(value)
  return tostring(value or ''):gsub('[%c]', ' ')
end

local function output()
  local lines, map, highlights = {}, {}, {}
  local function add(text, item, group)
    lines[#lines + 1] = text
    map[#lines] = item
    if group then highlights[#highlights + 1] = {line = #lines, group = group} end
  end
  return lines, map, highlights, add
end

function M.courses(groups, opts)
  opts = opts or {}
  local lines, map, highlights, add = output()
  add('COURSES', nil, 'BrightspaceHeader')
  for _, group in ipairs(groups or {}) do
    local visible = {}
    for _, course in ipairs(group.courses) do
      if opts.show_all or course.current then visible[#visible + 1] = course end
    end
    if #visible > 0 then
      add(clean(group.label), nil, 'BrightspaceHeader')
      for _, course in ipairs(visible) do
        local count = (opts.new_counts or {})[course.id] or 0
        local selected = course.id == opts.selected_id
        add((selected and '› ' or '  ') .. clean(course.code) .. ' ' .. clean(course.name)
          .. (count > 0 and ' (' .. count .. ')' or ''), {course_id = course.id},
          selected and 'BrightspaceNew' or nil)
      end
    end
  end
  if #lines == 1 then add('No courses loaded', nil, 'BrightspaceDim') end
  return lines, map, highlights
end

function M.content(course, tree, news, info, expanded)
  local lines, map, highlights, add = output()
  local store = require('brightspace.store')
  expanded = expanded or {}
  add(course and clean(course.name) or 'Select a course', nil, 'BrightspaceHeader')
  local function item_line(item, indent)
    local unseen = store.is_new(item)
    add(indent .. (unseen and '● ' or '  ') .. clean(item.title), item,
      unseen and 'BrightspaceNew' or nil)
  end
  add('Announcements', nil, 'BrightspaceHeader')
  for _, item in ipairs(news or {}) do item_line(item, '') end
  if not news or #news == 0 then add('  No announcements', nil, 'BrightspaceDim') end
  add('Course info', nil, 'BrightspaceHeader')
  if info then item_line(info, '') end
  local function walk(items, depth)
    for _, item in ipairs(items) do
      local indent = string.rep('  ', depth)
      if item.kind == 'module' then
        add(indent .. (expanded[item.key] and '▾ ' or '▸ ') .. clean(item.title),
          {module_key = item.key}, 'BrightspaceHeader')
        if expanded[item.key] then walk(item.children or {}, depth + 1) end
      else
        item_line(item, indent)
      end
    end
  end
  walk(tree or {}, 0)
  return lines, map, highlights
end

local function relative(due, now)
  local seconds = math.max(0, due - now)
  if seconds < 3600 then return math.floor(seconds / 60) .. 'm' end
  if seconds < 86400 then return math.floor(seconds / 3600) .. 'h' end
  return math.floor(seconds / 86400) .. 'd'
end

function M.panel(deadlines, new_items, now)
  local lines, map, highlights, add = output()
  local groups = {urgent = 'BrightspaceUrgent', soon = 'BrightspaceSoon', later = 'BrightspaceDim'}
  add('DEADLINES', nil, 'BrightspaceHeader')
  for _, deadline in ipairs(deadlines or {}) do
    add(relative(deadline.due, now or os.time()) .. ' ' .. clean(deadline.course_code) .. ' '
      .. clean(deadline.title), deadline.item, groups[deadline.urgency] or 'BrightspaceDim')
  end
  if not deadlines or #deadlines == 0 then add('No upcoming deadlines', nil, 'BrightspaceDim') end
  add('')
  add('NEW', nil, 'BrightspaceHeader')
  for _, item in ipairs(new_items or {}) do
    add('● ' .. clean(item.course_code) .. ' ' .. clean(item.title), item, 'BrightspaceNew')
  end
  if not new_items or #new_items == 0 then add('All caught up', nil, 'BrightspaceDim') end
  return lines, map, highlights
end

return M
