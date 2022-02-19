local api = vim.api

api.nvim_add_user_command('NvimTestRun', function(props)
  require('nvimdev').run_test(props)
end, {
  force = true,
  nargs = '*' -- shouldn't need this. Must be a bug.
})

api.nvim_add_user_command('NvimTestClear', function()
  require('nvimdev').clear_test_decor()
end, {
  force=true,
  nargs='*' -- shouldn't need this. Must be a bug.
})

vim.cmd[[
  augroup nvimdev_clint
    autocmd!
    autocmd BufRead * lua require('nvimdev.clint').attach()
  augroup END
]]
