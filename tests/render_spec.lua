describe('workspace rendering',function()
  local render
  before_each(function() render=require('brightspace.ui.render') end)
  it('hides past courses, marks selection and shows unseen counts',function()
    local groups={{label='2026/27 Q1',courses={{id=1,name='Current',code='TEST1001',current=true},{id=2,name='Past',current=false}}}}
    local lines,map=render.courses(groups,{selected_id=1,new_counts={[1]=3}})
    assert.is_truthy(table.concat(lines,'\n'):find('3',1,true))
    assert.is_nil(table.concat(lines,'\n'):find('Past',1,true))
    local found=false; for _,item in pairs(map) do if item.course_id==1 then found=true end end
    assert.is_true(found)
    lines=render.courses(groups,{show_all=true,new_counts={}})
    assert.is_truthy(table.concat(lines,'\n'):find('Past',1,true))
  end)
  it('collapses modules and maps expanded topics',function()
    local item={key='topic:1:2',kind='topic',course_id=1,title='Slides'}
    local tree={{key='module:1:1',kind='module',title='Week',children={item}}}
    local lines=render.content({name='Course'},tree,{},nil,{})
    assert.is_nil(table.concat(lines,'\n'):find('Slides',1,true))
    local map
    lines,map=render.content({name='Course'},tree,{},nil,{['module:1:1']=true})
    assert.is_truthy(table.concat(lines,'\n'):find('Slides',1,true))
    local found=false; for _,v in pairs(map) do if v==item then found=true end end
    assert.is_true(found)
  end)
  it('highlights urgent deadlines and maps their items',function()
    local item={key='deadline:1:1',kind='deadline',title='Homework'}
    local _,map,highlights=render.panel({{title='Homework',course_code='TEST1001',due=7200,urgency='urgent',item=item}},{},0)
    local found=false
    for _,h in ipairs(highlights) do if h.group=='BrightspaceUrgent' then found=true; assert.equals(item,map[h.line]) end end
    assert.is_true(found)
  end)
  it('marks only unseen items and sanitizes multiline titles',function()
    local store=require('brightspace.store')
    local old=store.is_new
    store.is_new=function(item) return item.key=='new' end
    local ok,err=pcall(function()
      local lines,map=render.content({name='Course'}, {}, {
        {key='new',kind='news',title='New\nannouncement'},
        {key='old',kind='news',title='Old announcement'},
      },nil,{})
      local markers=0
      for line,text in ipairs(lines) do
        if text:find('●',1,true) then markers=markers+1; assert.equals('new',map[line].key) end
        assert.is_nil(text:find('\n',1,true))
      end
      assert.equals(1,markers)
    end)
    store.is_new=old
    assert.is_true(ok,err)
  end)
end)
