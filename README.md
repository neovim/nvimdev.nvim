# nvimdev.nvim

Provides some nicities for hacking on [Neovim][]:

- Auto-detect Neovim source tree and `:cd` to the root.
- Build `ctags` on save.
  - Configured to work well with the generated sources.
- Relatively fast linting for C sources (clint.py).
  - Ignored errors list is kept up to date.
  - Gutter signs reflect importance of warnings.
- Linting for Lua using `luacheck` from the `.deps` directory.
- Filetype settings appropriate for Neovim's source code.


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

Automatically generate tags.  Tags will be written to `tmp/tags`.

For best results, use [universal-ctags][].

#### `g:nvimdev_auto_lint` (default `0`)

Automatically run `:Neomake` to lint sources after writing buffers.  Disabled
by default since cool people would have this already setup.

#### `g:nvimdev_build_readonly` (default `1`)

Set files loaded from `buffer/` or `.deps/` as readonly.


## Useful plugins

- [deoplete.nvim][]: Completions!
- [deoplete-clang2][]: (Electric Boogaloo) C Completions!  No configuration
  needed with Neovim's source.
- [wstrip.vim][]: Strip trailing whitespace on save, but only on lines you've
  changed.
- [helpful.vim][]: Displays version information for helptags.
- [dyslexic.vim][]: Mistyping variables in giant source files suck.


[Neovim]: https://github.com/neovim/neovim
[Neomake]: https://github.com/neomake/neomake
[universal-ctags]: https://github.com/universal-ctags/ctags
[deoplete.nvim]: https://github.com/Shougo/deoplete.nvim
[deoplete-clang2]: https://github.com/tweekmonster/deoplete-clang2
[wstrip.vim]: https://github.com/tweekmonster/wstrip.vim
[helpful.vim]: https://github.com/tweekmonster/helpful.vim
[dyslexic.vim]: https://github.com/tweekmonster/dyslexic.vim
