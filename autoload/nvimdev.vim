let s:plugin = expand('<sfile>:p:h:h')

function! nvimdev#setup_projectionist(bufpath) abort
  if exists('g:nvimdev_root') && stridx(a:bufpath, g:nvimdev_root) == 0
    " Support $VIM_SOURCE_DIR (used with Neovim's scripts/vim-patch.sh).
    let vim_src = $VIM_SOURCE_DIR
    if empty(vim_src)
      let vim_src = '.vim-src'
    endif
    call projectionist#append(g:nvimdev_root, {
          \ 'src/nvim/*': {
          \   'alternate': vim_src.'/src/{}',
          \ },
          \ '*': {
          \   'alternate': vim_src.'/{}',
          \ },
          \ vim_src.'/src/*': {
          \   'alternate': 'src/nvim/{}',
          \ },
          \ vim_src.'/*': {
          \   'alternate': '{}',
          \ },
          \ })
  endif
endfunction

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

function! nvimdev#init(path) abort
  let g:nvimdev_loaded = 2
  let g:nvimdev_root = a:path
  let s:path = a:path
  let s:errors_root = s:path . '/tmp/errors'

  call v:lua.require'nvimdev'.init(s:path)

  augroup nvimdev
    autocmd!
    autocmd BufRead,BufNewFile *.h set filetype=c
    autocmd FileType c call s:nvimdev_setup_ft()
    if get(g:, 'nvimdev_auto_ctags', 0)
      autocmd BufWritePost *.c,*.h,*.lua call s:build_db()
    endif
    if get(g:, 'nvimdev_build_readonly', 1)
      execute 'autocmd BufRead '.fnameescape(s:path).'/{build,.deps}/* '
            \ .'au CursorMoved <buffer> ++once setlocal readonly'
    endif

    " Setup/configure projectionist.
    if get(g:, 'loaded_projectionist', 0)
      autocmd User ProjectionistDetect call nvimdev#setup_projectionist(g:projectionist_file)

      " Init for first buffer, since this is called on BufEnter itself.
      call ProjectionistDetect(expand('%:p'))

      command! NvimDiff call nvimdev#diff()
    endif
  augroup END

  " Init for first buffer, since this is called on BufEnter itself.
  doautocmd nvimdev BufRead
  if &filetype ==# 'c'
    call s:nvimdev_setup_ft()
  endif

endfunction

function! s:nvimdev_setup_ft() abort
  if stridx(expand('<afile>:p'), s:path) != 0
    return
  endif

  setlocal expandtab
  setlocal shiftwidth=2
  setlocal softtabstop=2
  setlocal textwidth=80
  setlocal comments=:///,://
  setlocal cinoptions=0(
  setlocal commentstring=//\ %s
endfunction

let s:warned_about_missing_error_files = 0

function! s:build_db(...) abort
  if !a:0
    if exists('s:db_timer')
      call timer_stop(s:db_timer)
    endif
    redraw
    let s:db_timer = timer_start(1000, function('s:build_db'))
    return
  endif

  unlet! s:db_timer

  if get(g:, 'nvimdev_auto_ctags', 1) && executable(s:ctags_exe)
    call s:build_ctags_db()
  endif
endfunction

function! s:build_ctags_db() abort
  let cmd = [s:ctags_exe, '--languages=C,C++,Lua', '-R',
        \    '-I', 'EXTERN', '-I', 'INIT',
        \    '--exclude=.git*',
        \    'src', 'build/include', 'build/src/nvim/auto', '.deps/build/src']

  if exists('s:ctags_job')
    echo 'ctags' 'busy'
    return
  endif

  let s:ctags_job = jobstart(cmd, {
        \ 'db'      : 'ctags',
        \ 'cwd'     : s:path,
        \ 'on_exit' : function('s:build_db_job'),
        \ })
endfunction


function! s:build_db_job(job, data, event) dict abort
  " XXX: Log stdout/stderr on error without being obtrustive and without
  " overwriting results?
  if a:event ==# 'exit'
    unlet! s:{self.db . '_job'}
    if a:data != 0
      echohl ErrorMsg
      echo '[nvimdev]' self.db 'failed'
      echohl None
    endif
  endif
endfunction
