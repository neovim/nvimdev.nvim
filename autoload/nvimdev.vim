let s:plugin = expand('<sfile>:p:h:h')
let s:doc_url_base = 'https://raw.githubusercontent.com/neovim/doc/gh-pages/'
let s:errors_json = 'reports/clint/errors.json'
let s:ctags_job = 0


function! nvimdev#init(path) abort
  let g:nvimdev_loaded = 2
  let s:path = a:path
  let s:errors_root = s:path . '/tmp/errors'

  if get(g:, 'nvimdev_auto_cd', 1)
    execute 'cd' s:path
  endif

  let c_makers = []
  let s:ctags_file = s:path . '/tmp/tags'

  if exists('#clang2') && index(c_makers, 'clang') == -1
    " deoplete-clang2 (electric boogaloo) automatically sets compile flags.
    call add(c_makers, 'clang')
  endif

  let linter = {
        \ 'exe': s:path.'/src/clint.py',
        \ 'append_file': 0,
        \ 'cwd': s:path,
        \ 'errorformat': '%f:%l: %m',
        \ }

  function linter.fn(jobinfo) abort
    let bufname = expand('%')
    let errorfile = printf('%s/%s.json', s:errors_root, bufname)
    let maker = copy(self)
    let maker.args = []
    if filereadable(errorfile)
      let maker.args += ['--suppress-errors='.errorfile, bufname]
    else
      let maker.args += [bufname]
    endif
    return maker
  endfunction

  function linter.postprocess(entry) abort
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

  call add(c_makers, 'lint')
  let g:neomake_c_enabled_makers = c_makers

  let linter = neomake#makers#ft#lua#luacheck()
  call extend(linter, {
        \ 'exe': s:path . '/.deps/usr/bin/luacheck',
        \ 'cwd': s:path . '/test',
        \ 'remove_invalid_entries': 1,
        \ })
  let g:neomake_lua_nvimluacheck_maker = linter

  let lua_makers = get(g:, 'neomake_lua_enabled_makers', [])
  if !empty(lua_makers)
    let i = index(lua_makers, 'luacheck')
    if i >= 0
      call remove(lua_makers, i)
    endif
  endif
  call add(lua_makers, 'nvimluacheck')
  let g:neomake_lua_enabled_makers = lua_makers

  augroup nvimdev
    autocmd!
    autocmd BufRead,BufNewFile *.h set filetype=c
    if get(g:, 'nvimdev_auto_lint', 1)
      autocmd BufWritePost *.c,*.h,*.vim Neomake
    endif
    if get(g:, 'nvimdev_auto_ctags', 1)
      autocmd BufWritePost *.c,*.h,*.lua call s:build_ctags()
    endif
    if get(g:, 'nvimdev_build_readonly', 1)
      execute 'autocmd BufRead ' . s:path . '/build/* setlocal readonly nomodifiable'
      execute 'autocmd BufRead ' . s:path . '/.deps/* setlocal readonly nomodifiable'
    endif
  augroup END

  call nvimdev#update_clint_errors()
endfunction


function! nvimdev#update_clint_errors() abort
  if !executable('python3')
    echohl WarningMsg
    echo '[nvimdev] Python 3 is required to download lint errors'
    echohl None
    return
  endif

  let cmd = ['python3',
        \ s:plugin . '/scripts/download_errors.py',
        \ s:errors_root]
  let opts = {
        \ 'on_exit': function('s:errors_download_job'),
        \ }
  call jobstart(cmd, opts)
endfunction


function! s:errors_download_job(job, data, event) dict abort
  if a:event == 'exit'
    if a:data == 0
      echo '[nvimdev] clint: Updated ignored lint errors'
    elseif a:data != 200
      echohl WarningMsg
      echo '[nvimdev] clint: Failed to update ignored lint errors'
      echohl None
    endif
  endif
endfunction


function! s:build_ctags() abort
  let s:started = reltimefloat(reltime())
  if s:ctags_job
    echomsg 'ctags in progress'
    return
  endif

  let cmd = ['ctags', '--languages=C,C++,Lua', '-R',
        \    '-I', 'EXTERN', '-I', 'INIT',
        \    '--exclude=.git*',
        \    'src', 'build/include', 'build/src/nvim/auto', '.deps/build/src']
  let opt = {
        \ 'cwd': s:path,
        \ 'on_exit': function('s:build_ctags_job'),
        \ }

  call jobstart(cmd, opt)
endfunction


function! s:build_ctags_job(job, data, event) dict abort
  " XXX: Log stdout/stderr on error without being obtrustive and without
  " overwriting neomake results?
  if a:event == 'exit'
    let s:ctags_job = 0
    if a:data != 0
      echohl ErrorMsg
      echo '[nvimdev] ctags failed'
      echohl None
    endif
  endif
endfunction
