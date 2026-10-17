local M = {}
local time = require('brightspace.time')
function M.build(courses, per_course, calendar, now, days)
  local result, seen, current = {}, {}, {}
  local function add(course, title, date, id, url, body)
    local due = time.parse(date)
    if not due or due < now or due > now + days * 86400 then return end
    local key = tostring(course.id)..':'..title..':'..due
    if seen[key] then return end
    seen[key] = true
    local item = {key='deadline:'..course.id..':'..id,kind='deadline',course_id=course.id,title=title,
      due=due,modified=due,url=type(url)=='string' and url or nil,body_html=body}
    result[#result+1] = {title=title,course_code=course.code,due=due,item=item,
      urgency=due-now<86400 and 'urgent' or (due-now<3*86400 and 'soon' or 'later')}
  end
  for _, c in ipairs(courses) do
    if c.current then
      current[tostring(c.id)] = c
      local data = per_course[c.id] or per_course[tostring(c.id)] or {}
      for _, field in ipairs({'dropbox','quizzes'}) do
        for _, row in ipairs(data[field] or {}) do
          add(c,row.Name or row.Title or 'Deadline',row.DueDate,field..':'..tostring(row.Id or row.QuizId),nil,
            '<p>Due: '..tostring(row.DueDate)..'</p>')
        end
      end
    end
  end
  for _, event in ipairs(calendar or {}) do
    local row = event.EventDataInfo or event
    local c = current[tostring(row.OrgUnitId)]
    if c and (row.EventType == nil or row.EventType == 6) then
      local dates = event.Occurrences or {row}
      for _, occurrence in ipairs(dates) do
        add(c,row.Title or 'Event',occurrence.StartDateTime or row.StartDateTime,
          'calendar:'..tostring(row.CalendarEventId),row.CalendarEventViewUrl,row.Description)
      end
    end
  end
  table.sort(result, function(a,b) return a.due == b.due and a.title < b.title or a.due < b.due end)
  return result
end
return M
