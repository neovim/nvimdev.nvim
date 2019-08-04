let s:plugin = expand('<sfile>:p:h:h')
let s:neomake_warn = 1
let s:include_paths = [
      \ 'src',
      \ '.deps/usr/include',
      \ 'build/src/nvim/auto',
      \ 'build/include',
      \ ]


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
    if get(g:, 'nvimdev_auto_ctags', 0) || get(g:, 'nvimdev_auto_cscope', 0)
      autocmd BufWritePost *.c,*.h,*.lua call s:build_db()
    endif
    if get(g:, 'nvimdev_build_readonly', 1)
      if has('nvim-0.4.0')
        execute 'autocmd BufRead '.fnameescape(s:path).'/{build,.deps}/* '
              \ .'au CursorMoved <buffer> ++once setlocal readonly nomodifiable'
      else
        execute 'autocmd BufRead '.fnameescape(s:path).'/{build,.deps}/* '
              \ .'setlocal readonly nomodifiable'
      endif
    endif

    " Dummy event to avoid "No matching autocommands" below.
    autocmd BufRead <buffer> au! nvimdev BufRead <buffer>
  augroup END

  " Init for first buffer, since this is called on BufEnter itself.
  doautocmd nvimdev BufRead

  call nvimdev#update_clint_errors()
endfunction

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

  let linter = {
        \ 'name': 'nvimdev-clint',
        \ 'short_name': 'lint',
        \ 'exe': get(g:, 'python3_host_prog', 'python'),
        \ 'args': [s:path.'/src/clint.py'],
        \ 'cwd': s:path,
        \ 'errorformat': '%-GTotal errors%.%#,%f:%l: %m',
        \ 'remove_invalid_entries': get(g:, 'neomake_remove_invalid_entries', 0),
        \ 'output_stream': 'stdout',
        \ }

  function! linter.InitForJob(jobinfo) abort
    let bufname = substitute(expand('%:p'), s:path . '/' , '', '')
    let errorfile = printf('%s/%s.json', s:errors_root, bufname)
    let maker = copy(self)
    if filereadable(errorfile)
      let maker.args += ['--suppress-errors='.errorfile]
    endif
    return maker
  endfunction

  function! linter.supports_stdin(jobinfo) abort
    let bufname = substitute(expand('%:p'), s:path . '/' , '', '')
    let self.args += ['--stdin-filename', bufname]
    return 1
  endfunction

  function! linter.postprocess(entry) abort
    if a:entry.text =~# '\[\d]$'
      let a:entry.text = substitute(a:entry.text, '^\s*', '', '')
      let level = str2nr(matchstr(a:entry.text, '\d\ze]$'))
      if level >= 4
        let a:entry.type = 'E'
      elseif level >= 2
        let a:entry.type = 'W'
      else
        let a:entry.type = 'I'
      endif
    endif
  endfunction

  let g:neomake_c_lint_maker = linter

  if get(g:, 'nvimdev_auto_lint', 1)
	call add(c_makers, 'lint')
  endif
  let g:neomake_c_enabled_makers = c_makers

  " Use luacheck from .deps if not available/configured otherwise.
  if !exists('g:neomake_lua_luacheck_exe')
        \ && !executable('luacheck')
        \ && filereadable(s:path.'/.deps/usr/bin/luacheck')
    let g:neomake_lua_luacheck_exe = s:path.'/.deps/usr/bin/luacheck'
  endif
endfunction


function! nvimdev#update_clint_errors() abort
  let interpreter=get(g:,'python3_host_prog','python3')
  if !executable(interpreter)
    echohl WarningMsg
    echo '[nvimdev] Python 3 is required to download lint errors'
    echohl None
    return
  endif

  let cmd = [interpreter,
        \ s:plugin . '/scripts/download_errors.py',
        \ s:errors_root]
  let opts = {
        \ 'on_exit': function('s:errors_download_job'),
        \ }
  call jobstart(cmd, opts)
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
    elseif a:data != 200
      echohl WarningMsg
      echo '[nvimdev] clint: Failed to update ignored lint errors'
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
