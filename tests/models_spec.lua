local courses = require('brightspace.model.courses')
local content = require('brightspace.model.content')
local deadlines = require('brightspace.model.deadlines')
local time = require('brightspace.time')

describe('course models', function()
  local now = 1792108800 -- 2026-10-16 00:00 UTC
  it('parses UTC and offsets independently of local timezone', function()
    assert.equals(now, time.parse('2026-10-16T00:00:00Z'))
    assert.equals(now, time.parse('2026-10-16T02:00:00+02:00'))
    assert.is_nil(time.parse(vim.NIL))
  end)
  it('formats calendar timestamps with required milliseconds',function()
    assert.equals('2026-10-16T00:00:00.000Z',time.iso(1792108800))
  end)
  it('filters inaccessible units and selects current dated courses', function()
    local rows = {
      {OrgUnit={Id=100001,Type={Id=3},Code='TEST1001',Name='Example'},Access={StartDate='2026-09-01T00:00:00Z',EndDate='2026-11-01T00:00:00Z'}},
      {OrgUnit={Id=100002,Type={Id=3},Name='Past'},Access={StartDate='2025-09-01T00:00:00Z',EndDate='2025-11-01T00:00:00Z'}},
      {OrgUnit={Id=100003,Type={Id=2}},Access={}},
      {OrgUnit={Id=100004,Type={Id=3}},Access={CanAccess=false}},
    }
    local list = courses.normalize(rows, now)
    assert.equals(2, #list)
    assert.equals(100001, courses.current(list)[1].id)
    assert.equals('2026/27 Q1', courses.group(list)[1].label)
  end)
  it('uses named quarters when dates are missing', function()
    local list = courses.normalize({
      {OrgUnit={Id=100001,Type={Id=3},Name='Example (2025/26 Q3)'}},
      {OrgUnit={Id=100002,Type={Id=3},Name='Example (2026/27 Q1)'}},
    }, now)
    assert.equals('2025/26 Q3', list[1].quarter_label)
    assert.equals(100002, courses.current(list)[1].id)
  end)
  it('keeps nested topics in sort order and excludes hidden content', function()
    local tree = content.from_toc(100001, {Modules={{ModuleId=1,Title='Week',Topics={
      {TopicId=4,Title='Hidden',IsHidden=true},
      {TopicId=3,Title='Link',SortOrder=3,TypeIdentifier='Link',Url='https://example.org'},
      {TopicId=2,Title='Slides',SortOrder=1,TypeIdentifier='File',LastModifiedDate='2026-10-16T00:00:00Z'},
    },Modules={{ModuleId=5,Title='Nested',SortOrder=2,Topics={}}}}}})
    assert.equals(4, #content.flatten(tree))
    assert.equals('Slides', tree[1].children[1].title)
    assert.equals('module:100001:5', tree[1].children[2].key)
    assert.equals('Link', tree[1].children[3].file_type)
  end)
  it('sorts deadlines, applies urgency and removes calendar duplicates', function()
    local list = deadlines.build({{id=100001,code='TEST1001',current=true}}, {
      [100001]={dropbox={{Id=1,Name='Homework',DueDate=now+7200},{Id=2,Name='Old',DueDate=now-1}},
        quizzes={{QuizId=3,Name='Quiz',DueDate=now+2*86400},{QuizId=4,Name='Later',DueDate=now+10*86400},
          {QuizId=5,Name='Too far',DueDate=now+40*86400}}},
    }, {{CalendarEventId=8,OrgUnitId=100001,Title='Homework',StartDateTime=now+7200},
        {CalendarEventId=9,OrgUnitId=999,Title='Other course',StartDateTime=now+7200}}, now, 30)
    assert.equals(3, #list)
    assert.equals('urgent', list[1].urgency)
    assert.equals('soon', list[2].urgency)
    assert.equals('later', list[3].urgency)
  end)
end)

describe('model edge cases',function()
  it('retains undated courses in the current named quarter alongside dated courses',function()
    local list=courses.normalize({
      {OrgUnit={Id=1,Type={Id=3},Name='Dated'},Access={StartDate='2026-09-01T00:00:00Z',EndDate='2026-11-01T00:00:00Z'}},
      {OrgUnit={Id=2,Type={Id=3},Name='Undated (2026/27 Q1)'}},
      {OrgUnit={Id=3,Type={Id=3},Name='Future (2026/27 Q4)'}},
    },1792108800)
    local current=courses.current(list)
    assert.equals(2,#current)
    assert.equals(2,current[2].id)
  end)
  it('does not choose future quarter as current',function()
    local list=courses.normalize({
      {OrgUnit={Id=1,Type={Id=3},Name='Current (2026/27 Q1)'}},
      {OrgUnit={Id=2,Type={Id=3},Name='Future (2026/27 Q2)'}},
    },1792108800)
    assert.equals(1,courses.current(list)[1].id)
  end)
  it('uses text and creation time when optional news fields are JSON null',function()
    local items=require('brightspace.model.news').from_api(1,{{Id=1,Title='Note',
      Body={Html=vim.NIL,Text='Plain text'},LastModifiedDate=vim.NIL,StartDate='2026-10-16T00:00:00Z'}})
    assert.equals('Plain text',items[1].body_html)
    assert.equals(1792108800,items[1].modified)
  end)
end)
