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
  let file_hint = '/scripts/shadacat.py'
  let last_path = expand('%')
  let path = fnamemodify(last_path, ':h')

  while path != last_path
    if filereadable(path . file_hint)
      break
    endif

    let last_path = path
    let path = fnamemodify(path, ':h')
    if empty(path)
      break
    endif
  endwhile

  let found = path . file_hint
  if filereadable(found)
    call nvimdev#init(fnamemodify(found, ':p:h:h'))
  endif
endfunction

if get(g:, 'nvimdev_auto_init', 1)
  augroup nvimdev
    autocmd! BufEnter * call s:check_nvim()
  augroup END
endif
