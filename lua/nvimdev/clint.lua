local async = require('plenary.async.async')
local scheduler = require('plenary.async.util').scheduler

local subprocess0 = require('nvimdev.subprocess').subprocess

suppress_url_base = "https://raw.githubusercontent.com/neovim/doc/gh-pages/reports/clint"

local api = vim.api
local uv = vim.loop

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

local run = async.void(function(bufnr, check_file, suppress_file)
  scheduler()
  local name = api.nvim_buf_get_name(bufnr)
  local cwd = name:match('^(.*)/test/functional/.*$')

  local text = table.concat(
    api.nvim_buf_get_lines(bufnr, 0, -1, false),
    '\n')..'\n'

  local _, stdout = subprocess{
    command = vim.g.python3_host_prog or 'python',
    args = {
      './src/clint.py',
      '--suppress-errors='..(suppress_file or''),
      '--stdin-filename='..check_file,
      '-'
    },
    cwd = cwd,
    input = text,
  }

  local diags = parse_clint_output(stdout)
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
