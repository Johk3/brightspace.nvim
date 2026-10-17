local M = {}
function M.new()
  return {courses={},groups={},selected_id=nil,show_all=false,trees={},news={},info={},
    per_course={},calendar={},deadlines={},new_items={},new_counts={},expanded={},loading=false,generation=0}
end
return M
