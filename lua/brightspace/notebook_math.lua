local M = {}

local display_environments = {
  align = true,
  ['align*'] = true,
  aligned = true,
  cases = true,
  equation = true,
  ['equation*'] = true,
  gather = true,
  ['gather*'] = true,
  gathered = true,
  multline = true,
  ['multline*'] = true,
  split = true,
}

local function fenced_marker(line)
  return line:match('^%s*(```+)') or line:match('^%s*(~~~+)')
end

function M.normalize(lines)
  local result, fence, math_delimiter, environment = {}, nil, nil, nil
  local changed = false

  for _, line in ipairs(lines) do
    local marker = fenced_marker(line)
    if fence then
      result[#result + 1] = line
      if marker and marker:sub(1, 1) == fence:sub(1, 1) and #marker >= #fence then
        fence = nil
      end
    elseif marker then
      fence = marker
      result[#result + 1] = line
    else
      if not math_delimiter then
        local name = line:match('^%s*\\begin{([%w*]+)}%s*$')
        if name and display_environments[name] then
          environment = name
          result[#result + 1] = '$$'
          changed = true
        end
      end

      result[#result + 1] = line

      if environment and line:match('^%s*\\end{' .. environment:gsub('%*', '%%*') .. '}%s*$') then
        result[#result + 1] = '$$'
        environment = nil
        changed = true
      elseif not environment then
        -- Walk delimiters in order so single-line $$...$$ and \[...\] stay balanced.
        for _ in line:gmatch('%$%$') do
          if math_delimiter == '$$' then
            math_delimiter = nil
          elseif not math_delimiter then
            math_delimiter = '$$'
          end
        end
        if math_delimiter ~= '$$' then
          -- Skip \\[4pt]: a row break with spacing, not a delimiter.
          for at, bracket in line:gmatch('()\\([%[%]])') do
            if line:sub(at - 1, at - 1) ~= '\\' then
              math_delimiter = bracket == '[' and '\\[' or nil
            end
          end
        end
      end
    end
  end

  if environment then return lines, false end
  return changed and result or lines, changed
end

function M.normalize_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if not name:match('%.ipynb$') then return end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local normalized, changed = M.normalize(lines)
  if not changed then return end

  local modified = vim.bo[buf].modified
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, normalized)
  if not modified then vim.bo[buf].modified = false end
end

--- Multi-line $$ blocks as 0-based {first, last} rows, outside code fences.
function M.display_blocks(lines)
  local blocks, fence, start = {}, nil, nil
  for i, line in ipairs(lines) do
    local marker = fenced_marker(line)
    if fence then
      if marker and marker:sub(1, 1) == fence:sub(1, 1) and #marker >= #fence then fence = nil end
    elseif marker and not start then
      fence = marker
    else
      local _, count = line:gsub('%$%$', '')
      if count % 2 == 1 then
        if start then
          blocks[#blocks + 1] = {start, i - 1}
          start = nil
        else
          start = i - 1
        end
      end
    end
  end
  return blocks
end

local conceal_ns = vim.api.nvim_create_namespace('brightspace.notebook_math')
local block_cache = {}

-- render-markdown draws multi-line formulas above their source and leaves the
-- source visible. Hide the source of each rendered block, except the block under
-- the cursor so it stays editable. The opening line stays as a blank row because
-- the rendered lines are attached to it.
function M.conceal_display_math(buf, win)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, conceal_ns, 0, -1)
  local markdown_ns = vim.api.nvim_get_namespaces()['render-markdown.nvim']
  if not markdown_ns then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local cached = block_cache[buf]
  if not cached or cached.tick ~= tick then
    cached = {tick = tick, blocks = M.display_blocks(vim.api.nvim_buf_get_lines(buf, 0, -1, false))}
    block_cache[buf] = cached
  end
  local cursor = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
    and vim.api.nvim_win_get_cursor(win)[1] - 1
  for _, block in ipairs(cached.blocks) do
    local first, last = block[1], block[2]
    if not (cursor and cursor >= first and cursor <= last) then
      local rendered = false
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, markdown_ns, {first, 0}, {first, -1}, {details = true})) do
        if mark[4].virt_lines then rendered = true; break end
      end
      if rendered then
        local opening = vim.api.nvim_buf_get_lines(buf, first, first + 1, false)[1] or ''
        vim.api.nvim_buf_set_extmark(buf, conceal_ns, first, 0, {end_col = #opening, conceal = ''})
        for row = first + 1, last do
          vim.api.nvim_buf_set_extmark(buf, conceal_ns, row, 0, {conceal_lines = ''})
        end
      end
    end
  end
end

return M
