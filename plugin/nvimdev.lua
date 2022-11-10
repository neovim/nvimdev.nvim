local api = vim.api

api.nvim_create_user_command('NvimTestRun', function(props)
  require('nvimdev').run_test(props)
end, { force = true })

api.nvim_create_user_command('NvimTestClear', function()
  require('nvimdev').clear_test_decor()
end, { force = true })

api.nvim_create_autocmd('BufRead', {
  group = api.nvim_create_augroup('nvimdev_clint', {}),
  callback = function()
    require('nvimdev.clint').attach()
  end
})
