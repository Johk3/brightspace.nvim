local M = {}
local entities = {amp='&',lt='<',gt='>',quot='"',apos="'",nbsp=' '}
function M.decode(text)
  return (text:gsub('&(#?[%w]+);',function(code)
    if entities[code] then return entities[code] end
    local n = tonumber(code:match('^#(%d+)$')) or tonumber(code:match('^#[xX](%x+)$'),16)
    if n and n>0 and n<=0x10ffff and not (n>=0xd800 and n<=0xdfff) then return vim.fn.nr2char(n) end
    return '&'..code..';'
  end))
end
function M.render(html, width)
  width=math.max(10,width or 80)
  local text=tostring(html or ''):gsub('\r',''):gsub('<!%-%-.-%-%->','')
  for _,tag in ipairs({'script','style'}) do
    text=text:gsub('<'..tag..'[^>]*>.-</'..tag..'%s*>','')
  end
  text=text:gsub('<[aA]%s+([^>]+)>(.-)</[aA]%s*>',function(attrs,label)
    local url=attrs:match('[hH][rR][eE][fF]%s*=%s*["\'](.-)["\']')
    return label..(url and ' ('..url..')' or '')
  end)
  text=text:gsub('<([^>]+)>',function(raw)
    local closing,tag=raw:match('^%s*(/?)([%w]+)')
    tag=(tag or ''):lower()
    if tag=='li' then return closing=='' and '\n• ' or '' end
    if tag=='br' then return '\n' end
    if tag=='p' or tag=='div' or tag=='ul' or tag=='ol' or tag=='table' or tag:match('^h[1-6]$') then return '\n\n' end
    if tag=='tr' then return '\n' end
    if tag=='td' or tag=='th' then return ' ' end
    return ''
  end)
  text=M.decode(text):gsub('[ \t\f\v]+',' '):gsub(' *\n *','\n'):gsub('\n\n\n+','\n\n')
  text=text:gsub('^%s+',''):gsub('%s+$','')
  local lines={}
  for _,line in ipairs(vim.split(text,'\n',{plain=true})) do
    local current=''
    for word in line:gmatch('%S+') do
      if current~='' and vim.fn.strdisplaywidth(current..' '..word)>width then
        lines[#lines+1]=current; current=word
      else current=current=='' and word or current..' '..word end
    end
    lines[#lines+1]=current
  end
  return lines
end
return M
