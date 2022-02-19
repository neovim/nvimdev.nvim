local async = require('plenary.async.async')
local scheduler = require('plenary.async.util').scheduler

local api = vim.api

local M = {}

local ns = api.nvim_create_namespace('nvim_test')

local subprocess0 = require('nvimdev.subprocess').subprocess
local subprocess = async.wrap(subprocess0, 2)

local function get_test_lnum(lnum, inc_describe)
  lnum =  lnum or vim.fn.line('.')
  local test
  local test_lnum
  for i = lnum, 1, -1 do
    for _, pat in ipairs {
      "^%s*it%s*%(%s*['\"](.*)['\"']%s*,",
      inc_describe and "^%s*describe%s*%(%s*['\"](.*)['\"']%s*,"
    } do
      if pat then
        test = vim.fn.getline(i):match(pat)
        if test then
          test_lnum = i
          break
        end
      end
    end
    if test then
      break
    end
  end

  return test, test_lnum
end

local function get_test_lnums(all)
  local lnum = vim.fn.line(all and '$' or '.')

  local res = {}
  repeat
    local test, test_lnum = get_test_lnum(lnum, false)
    if test then
      res[#res+1] = {test, test_lnum}
      if not all then
        break
      end
      lnum = test_lnum - 1
    end
  until not test

  return res
end

local function filter_test_output(in_lines)
  local lines = {}
  local collect = false
  for _, l in ipairs(in_lines) do
    if not collect and l:match('%[ RUN') then
      collect = true
    end
    if collect and l ~= '' then
      if l:match('Tests exited non%-zero:') then
        break
      end
      lines[#lines+1] = l
    end
  end

  if #lines == 0 then
    lines = in_lines
  end
  return lines
end

local function create_virt_lines(lines)
  local virt_lines = {}
  for _, l in ipairs(lines) do
    virt_lines[#virt_lines+1] = {{l, 'ErrorMsg'}}
  end
  return virt_lines
end

local function set_diagnostics(bufnr, diags)
  local diags0 = {}

  for lnum, diag in pairs(diags) do
    diag.lnum = lnum - 1
    diags0[#diags0+1] = diag

    if diag.virt_lines then
      api.nvim_buf_set_extmark(bufnr, ns, lnum-1, -1, {
        id = lnum,
        virt_lines = diag.virt_lines,
        virt_lines_above = true
      })
    end
  end

  vim.diagnostic.set(ns, bufnr, diags0)
end

local function process_result(diag, code, stdout)
  if code > 0 then
    local stdout_lines = vim.split(stdout, '\n')
    local lines = filter_test_output(stdout_lines)
    diag.virt_lines = create_virt_lines(lines)
    diag.severity = vim.diagnostic.severity.ERROR
    diag.message = 'FAIL: '..diag.test
  else
    diag.severity = vim.diagnostic.severity.HINT
    diag.message = 'PASS: '..diag.test
  end
  return diag
end

local function notify_err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

local function running_diag(test)
  return {
    col = -1,
    test = test,
    message = 'RUN: '..test,
    severity = vim.diagnostic.severity.WARN
  }
end

M.run_test = async.void(function(props)
  local all = props.args == 'all'

  local name = api.nvim_buf_get_name(0)
  if not name:match('^.*/test/functional/.*$') then
    notify_err('Buffer is not an nvim functional test file')
    return
  end

  local targets = get_test_lnums(all)

  if #targets == 0 then
    notify_err('Could not find test')
    return
  end

  local cwd = name:match('^(.*)/test/functional/.*$')
  local cbuf = api.nvim_get_current_buf()

  vim.api.nvim_buf_clear_namespace(cbuf, ns, 0, -1)

  local diags = {}
  for i = #targets, 1, -1 do
    local test, test_lnum = unpack(targets[i])
    diags[test_lnum] = running_diag(test)
  end

  set_diagnostics(cbuf, diags)

  for i = #targets, 1, -1 do
    local test, test_lnum = unpack(targets[i])
    local code, stdout = subprocess{
      command = 'make',
      args = {
        'functionaltest',
        'TEST_FILE='..name,
        'TEST_FILTER='..test
      },
      cwd = cwd
    }

    scheduler()
    local diag = diags[test_lnum]
    diag = process_result(diag, code, stdout)
    set_diagnostics(cbuf, diags)
  end
end)

function M.clear_test_decor()
  api.nvim_buf_clear_namespace(0, ns, 0, -1)
  vim.cmd'redraw'
end

return M
