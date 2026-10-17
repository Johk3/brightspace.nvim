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
        if line:find('$$', 1, true) then
          math_delimiter = math_delimiter == '$$' and nil or '$$'
        elseif line:find('\\[', 1, true) then
          math_delimiter = math_delimiter == '\\[' and nil or '\\['
        elseif line:find('\\]', 1, true) then
          math_delimiter = nil
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

return M
