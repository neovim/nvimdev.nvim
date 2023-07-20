local async = require('nvimdev.async')
local scheduler = require('nvimdev.async').scheduler

local api = vim.api

local include_paths = {
  'src',
  '.deps/usr/include',
  'build/src/nvim/auto',
  'build/include',
}

local M = {}

local ns = api.nvim_create_namespace('nvim_test')

--- @type fun(cmd: string[], opt: table<string,any>): SystemCompleted
local system = async.wrap(vim.system, 3)

--- @param lnum integer
--- @param inc_describe boolean
--- @return string test
--- @return integer test_lnum
local function get_test_lnum(lnum, inc_describe)
  lnum =  lnum or vim.fn.line('.')
  local test --- @type string
  local test_lnum --- @type integer
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

--- @param all boolean
--- @return {[1]: string, [2]: integer}[]
local function get_test_lnums(all)
  local lnum = vim.fn.line(all and '$' or '.')

  local res = {} --- @type {[1]: string, [2]: integer}[]
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

---@param in_lines string[]
---@return string[]
local function filter_test_output(in_lines)
  local lines = {} --- @type string[]
  local collect = false
  for _, l in ipairs(in_lines) do
    if not collect and l:match('^RUN') then
      collect = true
    end
    if collect and l ~= '' then
      if l:match('NVIM_LOG_FILE') then
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

---@param bufnr integer
---@param diags Diagnostic[]
local function set_diagnostics(bufnr, diags)
  local diags0 = {} --- @type Diagnostic[]

  for lnum, diag in pairs(diags) do
    diag.lnum = lnum - 1
    diags0[#diags0+1] = diag
  end

  vim.diagnostic.set(ns, bufnr, diags0)
end

---@param diag Diagnostic
---@param code integer
---@param stdout string
local function process_result(diag, code, stdout)
  local stdout_lines = vim.split(stdout, '\n')
  local lines = filter_test_output(stdout_lines)
  if code > 0 then
    diag.severity = vim.diagnostic.severity.ERROR
    diag.message = 'FAIL: '..diag.test..'\n'..table.concat(lines, '\n')
  else
    diag.severity = vim.diagnostic.severity.HINT
    diag.message = 'PASS'
  end
end

local function notify_err(msg)
  vim.notify(msg, vim.log.levels.ERROR)
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

  api.nvim_buf_clear_namespace(cbuf, ns, 0, -1)

  local diags = {} --- @type Diagnostic[]
  for i = #targets, 1, -1 do
    local test, test_lnum = targets[i][1], targets[i][2]
    diags[test_lnum] = {
      col = 0,
      test = test,
      message = 'RUN: '..test,
      severity = vim.diagnostic.severity.WARN
    }
  end

  set_diagnostics(cbuf, diags)

  for i = #targets, 1, -1 do
    local test, test_lnum = targets[i][1], targets[i][2]
    local stdout_chunks = {} --- @type string[]
    local obj = system({
        'make',
        'functionaltest',
        'TEST_FILE='..name,
        'TEST_FILTER='..vim.pesc(test)
      }, {
        cwd = cwd,
        env = { TEST_COLORS = 0 },
        stdout = function(_err, data)
          if not data then
            return
          end

          stdout_chunks[#stdout_chunks+1] = data
          local diag = diags[test_lnum]
          diag.message = 'RUN: '..diag.test..'\n'..data
          vim.schedule(function()
            set_diagnostics(cbuf, diags)
          end)
        end
      })

    local stdout = table.concat(stdout_chunks, '')

    scheduler()
    local diag = diags[test_lnum]
    process_result(diag, obj.code, stdout)
    set_diagnostics(cbuf, diags)
  end
end)

function M.clear_test_decor()
  api.nvim_buf_clear_namespace(0, ns, 0, -1)
  vim.cmd'redraw'
end

local function setup_ft(path)
  if vim.fn.stridx(vim.fn.expand('<afile>:p'), path) ~= 0 then
    return
  end

  vim.bo.expandtab = true
  vim.bo.shiftwidth = 2
  vim.bo.softtabstop = 2
  vim.bo.textwidth = 80
  vim.bo.comments = ':///,://'
  vim.bo.commentstring='// %s'
  vim.bo.cinoptions='0('
end

local function setup_projectionist(bufpath)
  if vim.g.nvimdev_root and vim.fn.stridx(bufpath, vim.g.nvimdev_root) == 0 then
    -- Support $VIM_SOURCE_DIR (used with Neovim's scripts/vim-patch.sh).
    local vim_src = vim.env'VIM_SOURCE_DIR' --- @type string
    if vim_src == '' then
      vim_src = '.vim-src'
    end
    vim.call('projectionist#append', vim.g.nvimdev_root, {
      ['src/nvim/*'] = {
        alternate = vim_src..'/src/{}',
      },
      ['*'] = {
        alternate = vim_src..'/{}',
      },
      [vim_src..'/src/*'] = {
        alternate = 'src/nvim/{}',
      },
      [vim_src..'/*'] = {
        alternate = '{}',
      },
    })
  end
end

--- @type table<string,integer>
local h_autocmds = {}

--- @type table<string,integer>
local ft_autocmds = {}

function M.init(path)
  vim.g.nvimdev_loaded = 2
  vim.g.nvimdev_root = path

  if vim.g.nvimdev_auto_cd then
    vim.cmd.cd(path)
  end

  for _, inc in ipairs(include_paths) do
    vim.o.path = vim.o.path..','..string.format('%s/%s', path, inc)
  end

  if not h_autocmds[path] then
    h_autocmds[path] = api.nvim_create_autocmd({'BufEnter', 'BufNewFile'}, {
      group = 'nvimdev',
      pattern = '*.h',
      callback = function()
        if vim.fn.stridx(vim.fn.expand('<afile>:p'), path) ~= 0 then
          return
        end
        vim.bo.filetype = 'c'
      end
    })
  end

  if not ft_autocmds[path] then
    ft_autocmds[path] = api.nvim_create_autocmd('FileType', {
      group = 'nvimdev',
      pattern = 'c',
      callback = function()
        setup_ft(path)
      end
    })
  end

  if vim.g.loadded_projectionist then
    api.nvim_create_autocmd('User', {
      group = 'nvimdev',
      pattern = 'ProjectionistDetect',
      callback = function()
        setup_projectionist(vim.g.projectionist_file)
      end
    })

    vim.call('ProjectionistDetect', vim.fn.expand('%:p'))
    vim.cmd'command! NvimDiff call nvimdev#diff()'
  end

  -- Init for first buffer, since this is called on BufEnter itself.
  api.nvim_exec_autocmds('BufRead', { group = 'nvimdev' })

  if vim.bo.filetype == 'c' then
    setup_ft(path)
  end
end

return M
