local M = {}
function M.open(state)
  local entries={}
  for _,course in ipairs(state.courses) do
    entries[#entries+1]={course=course,label=(course.code or '')..'  '..course.name}
    for _,item in ipairs(require('brightspace.refresh').items(state,course.id)) do
      entries[#entries+1]={item=item,label=(course.code or '')..'  '..item.title}
    end
  end
  local function choose(entry)
    if not entry then return end
    if entry.course then
      local workspace=require('brightspace.ui.workspace')
      if not workspace.is_open() then require('brightspace.commands').run('open') end
      require('brightspace.refresh').select(state,entry.course.id,function() workspace.update(state) end)
    else
      require('brightspace.open').item(entry.item,function()
        require('brightspace.refresh').rebuild(state)
        require('brightspace.ui.workspace').update(state)
      end)
    end
  end
  local ok,pickers=pcall(require,'telescope.pickers')
  if not ok then return vim.ui.select(entries,{prompt='Brightspace',format_item=function(e) return e.label end},choose) end
  local actions=require('telescope.actions')
  pickers.new({}, {
    prompt_title='Brightspace',finder=require('telescope.finders').new_table({results=entries,
      entry_maker=function(e) return {value=e,display=e.label,ordinal=e.label} end}),
    sorter=require('telescope.config').values.generic_sorter({}),
    attach_mappings=function(buf)
      actions.select_default:replace(function()
        local selection=require('telescope.actions.state').get_selected_entry()
        actions.close(buf)
        choose(selection and selection.value)
      end)
      return true
    end,
  }):find()
end
return M
