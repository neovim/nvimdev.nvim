let s:plugin = expand('<sfile>:p:h:h')
let s:neomake_warn = 1
let s:include_paths = [
      \ 'src',
      \ '.deps/usr/include',
      \ 'build/src/nvim/auto',
      \ 'build/include',
      \ ]

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

  if get(g:, 'nvimdev_auto_cd', 1)
    execute 'cd' s:path
  endif

  for inc in s:include_paths
    let &path.=','.s:path.'/'.inc
  endfor

  if get(g:, 'loaded_neomake', 0)
    call s:setup_neomake()
  elseif s:neomake_warn
    echohl WarningMsg
    echomsg '[nvimdev] Neomake is not installed'
    echohl None
    let s:neomake_warn = 0
  endif

  let s:cscope_exe = get(g:, 'nvimdev_cscope_exe', 'cscope')
  let s:ctags_exe = get(g:, 'nvimdev_ctags_exe', 'ctags')

  if get(g:, 'nvimdev_auto_cscope', 0) && executable(s:cscope_exe)
    let &cscopeprg = s:cscope_exe
    let cscope_db = printf('%s/cscope.out', s:path)
    if filereadable(cscope_db)
      execute 'cscope add' cscope_db
    endif
  endif

  augroup nvimdev
    autocmd!
    autocmd BufRead,BufNewFile *.h set filetype=c
    autocmd FileType c call s:nvimdev_setup_ft()
    if get(g:, 'nvimdev_auto_ctags', 0) || get(g:, 'nvimdev_auto_cscope', 0)
      autocmd BufWritePost *.c,*.h,*.lua call s:build_db()
    endif
    if get(g:, 'nvimdev_build_readonly', 1)
      if has('nvim-0.4.0')
        execute 'autocmd BufRead '.fnameescape(s:path).'/{build,.deps}/* '
              \ .'au CursorMoved <buffer> ++once setlocal readonly'
      else
        execute 'autocmd BufRead '.fnameescape(s:path).'/{build,.deps}/* '
              \ .'setlocal readonly'
      endif
    endif

    if !has('nvim-0.4.0')
      " Dummy event to avoid "No matching autocommands" below.
      " Not required with neovim/neovim@45c34bd.
      autocmd BufRead <buffer> au! nvimdev BufRead <buffer>
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

  if get(g:, 'nvimdev_auto_cscope', 0)
    command! -buffer -nargs=? Callers call nvimdev#cscope_lookup_callers(<q-args>)
    command! -buffer -nargs=? Callees call nvimdev#cscope_lookup_callees(<q-args>)
  endif
endfunction

let s:warned_about_missing_error_files = 0

function! s:setup_neomake() abort
  let c_makers = []
  if exists('#clang2') && index(c_makers, 'clang') == -1
    " deoplete-clang2 (electric boogaloo) automatically sets compile flags.
    call add(c_makers, 'clang')
  endif

  " Use with :Neomake! make
  " make will try to build  both dependancies and nvim
  " Ignore entering .deps directory not to mess the quickfix-dirstack
  let l:efm_backup=&errorformat
  set errorformat&vim
  let s:tmp_efm='%-Gninja: Entering directory `.deps'',' . &errorformat
  let g:neomake_make_maker = {
        \ 'exe': 'make',
        \ 'args': ['VERBOSE=1'],
        \ 'errorformat': s:tmp_efm,
        \ 'remove_invalid_entries': get(g:, 'neomake_remove_invalid_entries', 0)
        \ }
  let &errorformat=efm_backup

  function! g:neomake_make_maker.postprocess(entry) abort
    if (a:entry.type ==? 'n')
      let a:entry.type = 'I'
    endif
  endfunction

  let g:neomake_c_enabled_makers = c_makers

  " Use luacheck from .deps if not available/configured otherwise.
  if !exists('g:neomake_lua_luacheck_exe')
        \ && !executable('luacheck')
        \ && filereadable(s:path.'/.deps/usr/bin/luacheck')
    let g:neomake_lua_luacheck_exe = s:path.'/.deps/usr/bin/luacheck'
  endif
endfunction


function! s:find_function_name() abort
  let name = ''
  let view = winsaveview()
  " Cheating a bit.  Expect an open curly brace at the beginning of a line
  " to mark the function body's starting position.
  if search('^{', 'bW')
    call search('\S\s*(', 'bW')
    let name = matchstr(getline('.'), '\k\+\s*\ze(')
  endif
  call winrestview(view)
  return name
endfunction


function! s:cscope_lookup(type, name) abort
  if empty(a:name)
    return
  endif

  execute 'cscope find' a:type a:name

  if &cscopequickfix =~# '\<'.a:type.'[-+]\?'
    let qflist = getqflist()
    let seen = []
    let final_qflist = []
    for entry in qflist
      if !entry.bufnr
        continue
      endif
      let key = printf('%s:%d', bufname(entry.bufnr), entry.lnum)
      if index(seen, key) == -1
        call add(final_qflist, entry)
      endif
    endfor

    call setqflist(final_qflist, 'r', 'cscope '.a:type)
    copen
  endif
endfunction


function! nvimdev#cscope_lookup_callers(...) abort
  let name = ''
  if a:0
    let name = a:1
  endif

  if empty(name)
    let name = s:find_function_name()
  endif

  call s:cscope_lookup('c', name)
endfunction


function! nvimdev#cscope_lookup_callees(...) abort
  let name = ''
  if a:0
    let name = a:1
  endif

  if empty(name)
    let name = s:find_function_name()
  endif

  call s:cscope_lookup('d', name)
endfunction


function! s:errors_download_job(job, data, event) dict abort
  if a:event ==# 'exit'
    if a:data == 0
      echo '[nvimdev] clint: Updated ignored lint errors'
    elseif a:data == 200
      echo '[nvimdev] clint: files are up-to-date'
    elseif !exists('v:exiting') || v:exiting is v:null
      " Only display error when not exiting (might be 143 (SIGTERM) then).
      echohl WarningMsg
      echo printf('[nvimdev] clint: Failed to update ignored lint errors (%d)', a:data)
      echohl None
    endif
  endif
endfunction


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

  if get(g:, 'nvimdev_auto_cscope', 0) && executable(s:cscope_exe)
    call s:build_cscope_db()
  endif
endfunction


function! s:start_db_job(db, cmd) abort
  let v = a:db . '_job'
  if exists('s:' . v)
    echo a:db 'busy'
    return
  endif

  let opt = {
        \ 'db': a:db,
        \ 'cwd': s:path,
        \ 'on_exit': function('s:build_db_job'),
        \ }

  let s:{v} = jobstart(a:cmd, opt)
endfunction


function! s:build_ctags_db() abort
  let cmd = [s:ctags_exe, '--languages=C,C++,Lua', '-R',
        \    '-I', 'EXTERN', '-I', 'INIT',
        \    '--exclude=.git*',
        \    'src', 'build/include', 'build/src/nvim/auto', '.deps/build/src']

  call s:start_db_job('ctags', cmd)
endfunction


function! s:build_cscope_db() abort
  let cmd = [s:cscope_exe, '-Rb']
  for inc in s:include_paths
    let cmd += ['-I', printf('%s/%s', s:path, inc)]
  endfor

  call s:start_db_job('cscope', cmd)
endfunction


function! s:build_db_job(job, data, event) dict abort
  " XXX: Log stdout/stderr on error without being obtrustive and without
  " overwriting neomake results?
  if a:event ==# 'exit'
    unlet! s:{self.db . '_job'}
    if a:data != 0
      echohl ErrorMsg
      echo '[nvimdev]' self.db 'failed'
      echohl None
    elseif self.db ==# 'cscope'
      let cscope_db = printf('%s/cscope.out', s:path)
      if filereadable(cscope_db)
        execute 'cscope add' cscope_db
      endif
    endif
  endif
endfunction
