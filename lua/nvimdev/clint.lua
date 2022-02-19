local async = require('plenary.async.async')
local scheduler = require('plenary.async.util').scheduler

local subprocess0 = require('nvimdev.subprocess').subprocess

local api = vim.api
local uv = vim.loop

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
  local name = api.nvim_buf_get_name(bufnr)
  local cwd = name:match('^(.*)/test/functional/.*$')

  local text = table.concat(
    api.nvim_buf_get_lines(bufnr, 0, -1, false),
    '\n')..'\n'

  local _, stdout = subprocess{
    command = vim.g.python3_host_prog or 'python',
    args = {
      './src/clint.py',
      '--suppress-errors='..suppress_file,
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

  local suppress_file = root..'/build/errors/'..base:gsub('[/.]', '%-')..'.json'

  if not uv.fs_stat(suppress_file) then
    print('[nvimdev] no file: '..suppress_file)
    return
  end

  -- This must be a relative path
  local check_file = 'src/nvim/'..base

  scheduler()
  api.nvim_buf_attach(bufnr, true, {
    on_lines = function(_, buf, _)
      run(buf, check_file, suppress_file)
    end
  })

  run(bufnr, check_file, suppress_file)
end)

return M
