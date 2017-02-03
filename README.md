# nvimdev.nvim

Provides some nicities for hacking on [Neovim][]:

- Auto-detect Neovim source tree and `:cd` to the root.
- Build `tags` on save.
  - Configured to work well with the generated sources.
- Build `cscope.out` on save.
  - Commands for looking up callers and callees from the current function.
- Relatively fast linting for C sources (clint.py).
  - Ignored errors list is kept up to date.
  - Gutter signs reflect importance of warnings.
- Linting for Lua using `luacheck` from the `.deps` directory.
- Filetype settings appropriate for Neovim's source code.


## Why?

Neovim has a pretty large code base and is full of Vim's rich and mysterious
history.  I have little knowledge of either and [wrote a script][gist] to help
me get around and automate some things.  People have shown interest in using
it, so it's now a plugin that will make maintenance easier.

## Installation

😑

## Requirements

- [Neomake][]
- Python 3

## Config

#### `g:nvimdev_auto_init` (default `1`)

Automatically enable when within the Neovim source tree, or one of its files
are loaded.

It can be manually enabled with:

```vim
call nvimdev#init("path/to/neovim")
```

It should always be set to the actual Neovim root.

#### `g:nvimdev_auto_cd` (default `1`)

Automatically `:cd` to the Neovim root after init.

#### `g:nvimdev_auto_ctags` (default `1`)

Automatically generate tags.

For best results, use [universal-ctags][].

#### `g:nvimdev_auto_cscope` (default `0`)

Automatically generate `cscope.out`.  Requires [cscope][].

The following commands will be added to `.c` buffers:

- `:Callers` - displays a list of locations calling a function
- `:Callees` - displays a list of functions called by a function

Each command takes an optional name.  Without arguments, the name of the
function at the cursor location is used.

If you want to display the results as quickfix items:

```vim
set cscopequickfix=s-,c-,d-,i-,t-,e-,a-
```

**Disclaimer:** I don't use `cscope` much and this didn't turn out as awesome
as I hoped it would.  Using the commands above, or `:cscope` with quickfix
enabled will cause the current buffer to jump to the first match.  Also, it
results in a bunch of duplicates since I think `cscope` indexes functions with
any aliased return types it finds.  I'm tempted to write a dumb script that
uses the `tags` file to build a cross refrence database.


#### `g:nvimdev_auto_lint` (default `0`)

Automatically run `:Neomake` to lint sources after writing buffers.  Disabled
by default since cool people would have this already setup.

#### `g:nvimdev_build_readonly` (default `1`)

Set files loaded from `build/` or `.deps/` as readonly.


## Useful plugins

- [deoplete.nvim][]: Completions!
- [deoplete-clang2][]: (Electric Boogaloo) C Completions!  No configuration
  needed with Neovim's source.
- [wstrip.vim][]: Strip trailing whitespace on save, but only on lines you've
  changed.
- [helpful.vim][]: Displays version information for helptags.
- [dyslexic.vim][]: Mistyping variables in giant source files suck.

## TODO

- Command to run tests


[Neovim]: https://github.com/neovim/neovim
[Neomake]: https://github.com/neomake/neomake
[universal-ctags]: https://github.com/universal-ctags/ctags
[cscope]: http://cscope.sourceforge.net/
[deoplete.nvim]: https://github.com/Shougo/deoplete.nvim
[deoplete-clang2]: https://github.com/tweekmonster/deoplete-clang2
[wstrip.vim]: https://github.com/tweekmonster/wstrip.vim
[helpful.vim]: https://github.com/tweekmonster/helpful.vim
[dyslexic.vim]: https://github.com/tweekmonster/dyslexic.vim
[gist]: https://gist.github.com/tweekmonster/8f9cfb36a56d7d1bb6a73e0f9589d81f
