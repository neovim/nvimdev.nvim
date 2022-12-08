function! nvimdev#diff() abort
  let alternate = projectionist#query_file('alternate')
  if empty(alternate)
    echohl WarningMsg
    echomsg '[nvimdev] no alternate file'
    echohl None
    return
  endif
  exe 'diffsplit' alternate[0]
endfunction
