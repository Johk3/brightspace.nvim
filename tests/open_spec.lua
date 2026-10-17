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
    for _,buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf):sub(1,#tmp)==tmp then vim.api.nvim_buf_delete(buf,{force=true}) end
    end
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
  it('opens a durable notebook and preserves edits after refresh and cache clearing',function()
    local calls=0
    local notebook='{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[]}'
    package.loaded['brightspace.api']={topic_file=function(_,_,dest,cb)
      calls=calls+1; vim.fn.writefile({notebook},dest)
      cb(nil,{filename='exercise.ipynb',content_type='application/octet-stream'})
    end}
    local item={key='topic:1:4',kind='topic',file_type='File',course_id=1,topic_id=4,modified=10,title='Exercise'}
    open.item(item)
    assert.is_true(vim.wait(1000,function() return vim.api.nvim_buf_get_name(0):match('%.ipynb$')~=nil end))
    local path=vim.api.nvim_buf_get_name(0)
    assert.equals(tmp..'/data/notebooks/1/4/exercise.ipynb',path)
    assert.equals('',vim.bo.buftype)
    vim.api.nvim_buf_set_lines(0,0,-1,false,{'my unsaved edits'})
    require('brightspace.store').clear_cache()
    item.modified=20
    open.item(item)
    assert.equals(path,vim.api.nvim_buf_get_name(0))
    assert.same({'my unsaved edits'},vim.api.nvim_buf_get_lines(0,0,-1,false))
    assert.equals(1,calls)
    assert.equals(0,#launches)
    assert.equals(notebook,vim.fn.readfile(path)[1])
  end)
  it('recognizes notebook URLs without a download filename',function()
    package.loaded['brightspace.api']={topic_file=function(_,_,dest,cb)
      vim.fn.writefile({'{"nbformat":4,"metadata":{},"cells":[]}'},dest)
      cb(nil,{content_type='application/octet-stream'})
    end}
    open.item({key='topic:1:5',kind='topic',file_type='File',course_id=1,topic_id=5,
      url='/content/Practice.IPYNB?download=1',title='Practice'})
    assert.is_true(vim.wait(1000,function() return vim.api.nvim_buf_get_name(0):match('%.ipynb$')~=nil end))
    assert.equals(0,#launches)
  end)
  it('recognizes notebook MIME types and sanitizes server filenames',function()
    package.loaded['brightspace.api']={topic_file=function(_,_,dest,cb)
      vim.fn.writefile({'{"nbformat":4,"metadata":{},"cells":[]}'},dest)
      cb(nil,{filename='../../exercise',content_type='application/x-ipynb+json; charset=utf-8'})
    end}
    open.item({key='topic:1:7',kind='topic',file_type='File',course_id=1,topic_id=7})
    assert.is_true(vim.wait(1000,function() return vim.api.nvim_buf_get_name(0):match('%.ipynb$')~=nil end))
    assert.equals(tmp..'/data/notebooks/1/7/exercise.ipynb',vim.api.nvim_buf_get_name(0))
    assert.equals(384,bit.band(vim.uv.fs_stat(vim.api.nvim_buf_get_name(0)).mode,511))
  end)
  it('keeps notebook working copies in a configurable directory',function()
    local config=require('brightspace.config')
    local previous=config.get().notebook_dir
    config.get().notebook_dir=tmp..'/My notebooks'
    local source=tmp..'/download'
    vim.fn.mkdir(tmp,'p')
    vim.fn.writefile({'{"nbformat":4,"metadata":{},"cells":[]}'},source)
    local path,err=require('brightspace.notebook').keep({course_id=2,topic_id=8},source,'work.ipynb')
    config.get().notebook_dir=previous
    assert.is_nil(err)
    assert.equals(tmp..'/My notebooks/2/8/work.ipynb',path)
    assert.equals(1,vim.fn.filereadable(path))
  end)
  it('rejects invalid notebook downloads before opening them',function()
    package.loaded['brightspace.api']={topic_file=function(_,_,dest,cb)
      vim.fn.writefile({'not a notebook'},dest); cb(nil,{filename='bad.ipynb'})
    end}
    open.item({key='topic:1:6',kind='topic',file_type='File',course_id=1,topic_id=6})
    assert.is_true(vim.wait(1000,function() return #messages>0 end))
    assert.equals(0,#launches)
    assert.same({},vim.fn.glob(tmp..'/data/notebooks/**/*.ipynb',false,true))
  end)
  it('refuses executable and local link schemes',function()
    open.item({kind='topic',file_type='Link',url='file:///etc/passwd',key='x'})
    assert.equals(0,#launches)
    assert.equals(1,#messages)
  end)
end)
