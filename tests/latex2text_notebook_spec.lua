describe('notebook LaTeX converter', function()
  local script = vim.fn.getcwd() .. '/scripts/latex2text-notebook.py'
  local python = os.getenv('BRIGHTSPACE_TEST_PYTHON') or (vim.fn.stdpath('data') .. '/notebook-venv/bin/python')
  local available = vim.fn.executable(python) == 1
    and vim.system({ python, '-c', 'import pylatexenc' }):wait().code == 0
  local nbsp = '\194\160'

  local function convert(source)
    local result = vim.system({ python, '-I', script }, { stdin = source, text = true }):wait()
    assert.equals(0, result.code, result.stderr)
    return (result.stdout:gsub(nbsp, ' '))
  end

  local function check(name, fn)
    if available then return it(name, fn) end
    pending(name .. ' (needs python with pylatexenc; set BRIGHTSPACE_TEST_PYTHON)')
  end

  check('keeps fraction grouping', function()
    assert.equals('Θ/T = 1/(I × s^2 + c × s)', convert('\\frac{\\Theta}{T} = \\frac{1}{I \\times s^{2} + c \\times s}'))
    assert.equals('1/((I × τ)s^3 + c × s)', convert('\\frac{1}{(I \\times \\tau)s^{3} + c \\times s}'))
    assert.equals('ṗ = -c_x/I_x p + 1/I_x T_x', convert('\\dot p = -\\frac{c_x}{I_x}p + \\frac{1}{I_x}T_x'))
  end)

  check('spaces relations and keeps spaces after accented symbols', function()
    assert.equals('T - c × θ̇ = I × θ̈', convert('T - c \\times \\dot{\\theta} = I \\times \\ddot{\\theta}'))
    assert.equals('Iθ̈ + cθ̇ = T', convert('I\\ddot\\theta + c\\dot\\theta = T'))
    assert.equals('τ ≈ 0.01 s', convert('\\tau \\approx 0.01 \\text{s}'))
    assert.equals('t ≥ t_0', convert('t\\ge t_0'))
  end)

  check('groups multi-token scripts and separates scripts from following symbols', function()
    assert.equals('∑_(i = 0)^n x_i', convert('\\sum_{i=0}^{n} x_i'))
    assert.equals('𝒥^(-1) Γ', convert('\\mathcal{J}^{-1}\\Gamma'))
    assert.equals('x_i p + T_motor', convert('x_ip + T_{motor}'))
  end)

  check('renders aligned rows without blank lines and treats source newlines as spaces', function()
    assert.equals('I_x ṗ = (I_y - I_z) q r\nI_y q̇ = p r',
      convert('\\begin{aligned}\nI_x\\dot p &= (I_y - I_z)\\,q\\,r\\\\\nI_y\\dot q &= p\\,r\n\\end{aligned}'))
    assert.equals('u = a = b', convert('u = a\n  = b'))
  end)

  check('renders cases and matrices', function()
    assert.equals('⎧ x   x > 0\n⎩ -x  otherwise',
      convert('\\begin{cases} x & x > 0 \\\\ -x & \\text{otherwise} \\end{cases}'))
    assert.equals('⎧ a = 1\n⎨ b = 2\n⎩ c = 3', convert('\\begin{cases}\na = 1 \\\\\nb = 2 \\\\\nc = 3 \\\\\n\\end{cases}'))
    assert.equals('K = [kp, 0; 0, kp]', convert('K = \\begin{bmatrix}\nkp & 0 \\\\[4pt]\n0 & kp\n\\end{bmatrix}'))
  end)
end)
