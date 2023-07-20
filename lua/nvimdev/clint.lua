local async = require('nvimdev.async')
local scheduler = async.scheduler

local api = vim.api
local uv = vim.loop

local has_uncrustify = vim.fn.executable('uncrustify')

local ns = api.nvim_create_namespace('nvim_test_clint')

--- @type fun(cmd: string[], opt: SystemOpts): SystemCompleted
local system = async.wrap(vim.system, 3)

--- @param output string?
--- @return Diagnostic[]
local function parse_clint_output(output)
  local diags = {} --- @type Diagnostic[]
  for _, line in ipairs(vim.split(output or '', "\n")) do
    local ok, _, lnum, msg, level = line:find('^[^:]*:(%d+): (.*) %[(%d)%]$')
    if ok then
      level = tonumber(level)
      lnum = tonumber(lnum)
      local severity --- @type DiagnosticSeverity
      if level >= 4 then
        severity = vim.diagnostic.severity.ERROR
      elseif level >= 2 then
        severity = vim.diagnostic.severity.WARN
      else
        severity = vim.diagnostic.severity.INFO
      end
      diags[#diags+1] = {
        lnum = lnum-1,
        col = 0,
        message = msg,
        severity = severity,
        source = "clint",
      }
    end
  end
  return diags
end

local M = {}

local function get_clint_diags(check_file, cwd, text)
  local obj = system({
    vim.g.python3_host_prog or 'python3',
    './src/clint.py',
    '--verbose=0',
    '--stdin-filename='..check_file,
    '-'
  }, {
    cwd = cwd,
    stdin = text,
  })

  return parse_clint_output(obj.stdout)
end

--- @param check_file string
--- @param cwd string
--- @param text string
--- @param lines string[]
--- @return Diagnostic[]
local function get_uncrustify_diags(check_file, cwd, text, lines)
  local obj = system({
    'uncrustify',
    '-q',
    '-l', 'C',
    '-c', './src/uncrustify.cfg',
    '--check',
    '--assume', check_file,
  }, {
    stdin = text,
    stderr = false,
    cwd = cwd,
  })

  --- @type Diagnostic[]
  local ret = {}

  if obj.code > 0 then
    local hunks = vim.diff(text, obj.stdout, {result_type = 'indices'})
    local stdout_lines = vim.split(obj.stdout, '\n')

    for _, hunk in ipairs(hunks) do
      ret[#ret+1] = {
        lnum    = hunk[1] - 1,
        col     = 0,
        source = 'uncrustify',
        message = table.concat({
          'Uncrustify error:',
          '  -'..lines[hunk[1]],
          '  +'..(stdout_lines[hunk[3]] or '???')
        }, '\n')
      }
    end
  end

  return ret
end

local run = async.void(function(bufnr, check_file)
  scheduler()
  local name = api.nvim_buf_get_name(bufnr)
  local cwd = name:match('^(.*)/src/nvim/.*$')

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, '\n')..'\n'

  local diags = get_clint_diags(check_file, cwd, text)

  if has_uncrustify then
    vim.list_extend(diags, get_uncrustify_diags(check_file, cwd, text, lines))
  end

  scheduler()
  vim.diagnostic.set(ns, bufnr, diags)
end)

local function debounce_trailing(ms, fn)
  local timer = assert(vim.uv.new_timer())
  api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      if timer and not timer:is_closing() then
        timer:close()
      end
    end
  })
  return function(...)
    local argv = {...}
    timer:start(ms, 0, function()
      timer:stop()
      fn(unpack(argv))
    end)
  end
end

local run_debounced = debounce_trailing(500, run)

M.attach = async.void(function()
  local bufnr = api.nvim_get_current_buf()

  if vim.bo[bufnr].filetype ~= 'c' then
    return
  end

  local name = api.nvim_buf_get_name(bufnr)

  --- @type integer, any, string, string
  local ok, _, root, base = name:find('(.*)/src/nvim/(.*)')
  if not ok then
    return
  end

  if not root
    or not uv.fs_stat(root..'/build')
    or not uv.fs_stat(root..'/src/nvim') then
    return
  end

  -- This must be a relative path
  local check_file = 'src/nvim/'..base

  scheduler()
  api.nvim_buf_attach(bufnr, true, {
    on_lines = function(_, buf, _)
      run_debounced(buf, check_file)
    end
  })

  run(bufnr, check_file)
end)

return M
