if exists('g:nvimdev_loaded')
  finish
endif

let g:nvimdev_loaded = 1

function! s:check_nvim() abort
  if !empty(&buftype)
    return
  endif

  " Look for 'scripts/shadacat.py'.
  " It's a pretty unique filename and it sounds cool, like 'shadow cat'.
  let file = findfile('scripts/shadacat.py', '.;')
  if !empty(file) && filereadable('scripts/shadacat.py')
    call nvimdev#init(fnamemodify(file, ':p:h:h'))
  endif
endfunction

if get(g:, 'nvimdev_auto_init', 1)
  augroup nvimdev
    autocmd! BufEnter * call s:check_nvim()
  augroup END
endif
