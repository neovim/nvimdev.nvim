if get(g:, 'nvimdev_loaded', 0) != 2
  finish
endif

setlocal expandtab
setlocal shiftwidth=2
setlocal softtabstop=2
setlocal textwidth=80
setlocal comments=:///,://
setlocal modelines=0
setlocal cinoptions=0(
setlocal commentstring=//\ %s

if get(g:, 'nvimdev_auto_cscope', 0)
  command! -buffer -nargs=? Callers call nvimdev#cscope_lookup_callers(<q-args>)
  command! -buffer -nargs=? Callees call nvimdev#cscope_lookup_callees(<q-args>)
endif
