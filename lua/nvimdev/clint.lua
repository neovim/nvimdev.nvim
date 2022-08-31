local async = require('nvimdev.async')
local scheduler = async.scheduler

local subprocess0 = require('nvimdev.subprocess').subprocess

local suppress_url_base = "https://raw.githubusercontent.com/neovim/doc/gh-pages/reports/clint"

local api = vim.api
local uv = vim.loop

local has_uncrustify = vim.fn.executable('uncrustify')

local function log(msg)
  vim.schedule(function()
    print('[nvimdev] '..msg)
  end)
end

local ns = api.nvim_create_namespace('nvim_test_clint')

local subprocess = async.wrap(subprocess0, 2)

local function parse_clint_output(output)
  local diags = {}
  for _, line in ipairs(vim.split(output or '', "\n")) do
    local ok, _, lnum, msg, level = line:find('^[^:]*:(%d+): (.*) %[(%d)%]$')
    if ok then
      level = tonumber(level)
      lnum = tonumber(lnum)
      local severity
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

local function get_clint_diags(check_file, suppress_file, cwd, text)
  local _, stdout = subprocess{
    command = vim.g.python3_host_prog or 'python3',
    args = {
      './src/clint.py',
      '--suppress-errors='..(suppress_file or''),
      '--stdin-filename='..check_file,
      '-'
    },
    cwd = cwd,
    input = text,
  }

  return parse_clint_output(stdout)
end

local function get_uncrustify_diags(check_file, cwd, text, lines)
  local code, stdout = subprocess{
    command = 'uncrustify',
    stderr = false,
    args = {
      '-q',
      '-l', 'C',
      '-c', './src/uncrustify.cfg',
      '--check',
      '--assume', check_file,
    },
    cwd = cwd,
    input = text,
  }

  local ret = {}

  if code > 0 then
    local hunks = vim.diff(text, stdout, {result_type = 'indices'})
    local stdout_lines = vim.split(stdout, '\n')

    for _, hunk in ipairs(hunks) do
      ret[#ret+1] = {
        lnum    = hunk[1] - 1,
        col     = 0,
        source = 'uncrustify',
        message = table.concat({
          'Uncrustify error:',
          '  -'..lines[hunk[1]],
          '  +'..stdout_lines[hunk[3]]
        }, '\n')
      }
    end
  end

  return ret
end

local run = async.void(function(bufnr, check_file, suppress_file)
  scheduler()
  local name = api.nvim_buf_get_name(bufnr)
  local cwd = name:match('^(.*)/src/nvim/.*$')

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, '\n')..'\n'

  local diags = get_clint_diags(check_file, suppress_file, cwd, text)

  if has_uncrustify then
    vim.list_extend(diags, get_uncrustify_diags(check_file, cwd, text, lines))
  end

  scheduler()
  vim.diagnostic.set(ns, bufnr, diags)
end)

local function download_suppress_file(url, output)
  return subprocess{
    command = 'wget',
    args = { url, '--output-document', output }
  }
end

local function debounce_trailing(ms, fn)
  local timer = vim.loop.new_timer()
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

  local ok, _, root, base = name:find('(.*)/src/nvim/(.*)')
  if not ok then
    return
  end

  if not root
    or not uv.fs_stat(root..'/build/errors')
    or not uv.fs_stat(root..'/src/nvim') then
    return
  end

  local errors_base = base:gsub('[/.]', '%-')..'.json'
  local suppress_file = root..'/build/errors/'..errors_base

  if not uv.fs_stat(suppress_file) then
    log('no file: '..suppress_file)

    local code = download_suppress_file(
      suppress_url_base ..'/'..errors_base, suppress_file)
    if code == 0 then
      log('successfully downloaded suppress file for '..base)
    else
      log('failed to download: '..errors_base)
      os.remove(suppress_file)
      suppress_file = nil
    end
  end

  -- This must be a relative path
  local check_file = 'src/nvim/'..base

  scheduler()
  api.nvim_buf_attach(bufnr, true, {
    on_lines = function(_, buf, _)
      run_debounced(buf, check_file, suppress_file)
    end
  })

  run(bufnr, check_file, suppress_file)
end)

return M
