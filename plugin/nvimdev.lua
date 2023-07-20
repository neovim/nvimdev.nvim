local api = vim.api

api.nvim_create_user_command('NvimTestRun', function(props)
  require('nvimdev').run_test(props)
end, { force = true, nargs = '*' })

api.nvim_create_user_command('NvimTestClear', function()
  require('nvimdev').clear_test_decor()
end, { force = true })

api.nvim_create_autocmd('BufRead', {
  group = api.nvim_create_augroup('nvimdev_clint', {}),
  callback = function()
    require('nvimdev.clint').attach()
  end
})

vim.api.nvim_create_autocmd('BufEnter', {
  group = api.nvim_create_augroup('nvimdev', {}),
  callback = function()
    if vim.bo.buftype ~= '' then
      return
    end

    -- Look for 'scripts/shadacat.py'.
    -- It's a pretty unique filename and it sounds cool, like 'shadow cat'.
    local file_hint = '/scripts/shadacat.py'
    local last_path = vim.fn.expand('%')
    local path = vim.fn.fnamemodify(last_path, ':p:h')

    local found --- @type string?
    while path ~= last_path do
      if vim.fn.filereadable(path .. file_hint) then
        found = path
        break
      end

      last_path = path
      path = vim.fn.fnamemodify(path, ':h')
      if path == '' then
        break
      end
    end

    if found then
      require'nvimdev'.init(found)
    end
  end
})
