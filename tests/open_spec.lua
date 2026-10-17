local html = require('brightspace.html2text')
describe('html text rendering', function()
  it('renders blocks, links and entities without scripts', function()
    local lines = html.render('<p>Hello&nbsp;<b>world</b></p><ul><li>A</li><li>B</li></ul><a href="https://x.y">link</a><script>bad()</script>',80)
    assert.same({'Hello world','','• A','• B','','link (https://x.y)'},lines)
  end)
end)
describe('opening items', function()
  local open, saved_api, saved_system, saved_notify, tmp, saved_cache, saved_data, messages, launches
  before_each(function()
    tmp=vim.fn.tempname()
    saved_cache,saved_data=vim.env.BRIGHTSPACE_CACHE_DIR,vim.env.BRIGHTSPACE_DATA_DIR
    vim.env.BRIGHTSPACE_CACHE_DIR,vim.env.BRIGHTSPACE_DATA_DIR=tmp..'/cache',tmp..'/data'
    saved_api=package.loaded['brightspace.api']
    saved_system,saved_notify=vim.system,vim.notify
    messages,launches={},{}
    vim.notify=function(s) messages[#messages+1]=s end
    vim.system=function(cmd) launches[#launches+1]=cmd; return {} end
    package.loaded['brightspace.open']=nil
    open=require('brightspace.open')
  end)
  after_each(function()
    package.loaded['brightspace.api']=saved_api
    vim.system,vim.notify=saved_system,saved_notify
    vim.env.BRIGHTSPACE_CACHE_DIR,vim.env.BRIGHTSPACE_DATA_DIR=saved_cache,saved_data
    vim.fn.delete(tmp,'rf')
  end)
  it('never opens an HTML login response as a file', function()
    package.loaded['brightspace.api']={topic_file=function(_,_,_,cb) cb('not_a_file') end}
    open.item({key='topic:1:2',kind='topic',file_type='File',course_id=1,topic_id=2,title='Slides'})
    vim.wait(100,function() return #messages>0 end)
    assert.equals(0,#launches)
    assert.equals(1,#messages)
  end)
  it('downloads once then opens cached files without another request', function()
    local calls=0
    package.loaded['brightspace.api']={topic_file=function(_,_,dest,cb)
      calls=calls+1; vim.fn.writefile({'%PDF-fake'},dest); cb(nil,{content_type='application/pdf',filename='slides.pdf'})
    end}
    local item={key='topic:1:2',kind='topic',file_type='File',course_id=1,topic_id=2,modified=10,title='Slides'}
    open.item(item)
    vim.wait(100,function() return #launches==1 end)
    open.item(item)
    vim.wait(100,function() return #launches==2 end)
    assert.equals(1,calls)
    assert.equals(2,#launches)
    assert.is_truthy(launches[1][2]:match('%.pdf$'))
  end)
  it('renders HTML course topics inside Neovim without launching a viewer',function()
    package.loaded['brightspace.api']={topic_html=function(_,_,cb) cb(nil,'<h1>Course page</h1><p>Readable text</p>') end}
    local previous=vim.api.nvim_get_current_win()
    open.item({key='topic:1:3',kind='topic',file_type='File',course_id=1,topic_id=3,
      title='Page',url='/content/page.html'})
    assert.is_true(vim.wait(1000,function() return vim.api.nvim_get_current_win()~=previous end))
    local win=vim.api.nvim_get_current_win()
    local lines=vim.api.nvim_buf_get_lines(0,0,-1,false)
    assert.is_truthy(table.concat(lines,'\n'):find('Readable text',1,true))
    assert.equals(0,#launches)
    vim.api.nvim_win_close(win,true)
  end)
  it('refuses executable and local link schemes',function()
    open.item({kind='topic',file_type='Link',url='file:///etc/passwd',key='x'})
    assert.equals(0,#launches)
    assert.equals(1,#messages)
  end)
end)
