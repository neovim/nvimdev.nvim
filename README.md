# nvimdev.nvim

Provides some nicities for hacking on [Neovim][]:

- Auto-detect Neovim source tree and `:cd` to the root.
- Fast linting for C sources (clint.py and uncrustify).
  - Uses `vim.diagnostic`
- Filetype settings appropriate for Neovim's source code.
- Hook into [vim-projectionist]: configure alternate files for the ".vim-src"
  directory, and a command to diff against the same file in Vim.
- Add commands `NvimTestRun` and `NvimTestClear` for running functional tests directly in the buffer.


## Why?

Neovim has a pretty large code base and is full of Vim's rich and mysterious
history.  I have little knowledge of either and [wrote a script][gist] to help
me get around and automate some things.  People have shown interest in using
it, so it's now a plugin that will make maintenance easier.

## Installation

😑

## Requirements

- Python 3
- [plenary.nvim][]

## Config

#### `g:nvimdev_auto_cd` (default `1`)

Automatically `:cd` to the Neovim root after init.

## Commands

`NvimTestRun [all]`: Run the test in the buffer the cursor is inside. Works for `it` and `describe` blocks.

`NvimTestClear`: Clear test result decorations in buffer

## Useful plugins

- [nvim-cmp][]: Completions!
- [cmp-nvim-lsp][]: LSP completion source!
- [nvim-lspconfig][]: LSP configuration for [clangd][] and [sumneko-lua-lsp][].
- [nvim-treesitter][]: Better syntax highlighting for C and Lua files.
- [neodev.nvim][]: Neovim Lua development.

[Neovim]: https://github.com/neovim/neovim
[nvim-treesitter]: https://github.com/nvim-treesitter/nvim-treesitter
[nvim-cmp]: https://github.com/hrsh7th/nvim-cmp
[cmp-nvim-lsp]: hrsh7th/cmp-nvim-lsp
[nvim-lspconfig]: https://github.com/neovim/nvim-lspconfig
[sumneko-lua-lsp]: https://github.com/sumneko/lua-language-server
[clangd]: https://clangd.llvm.org
[gist]: https://gist.github.com/tweekmonster/8f9cfb36a56d7d1bb6a73e0f9589d81f
[vim-projectionist]: https://github.com/tpope/vim-projectionist
[plenary.nvim]: https://github.com/nvim-lua/plenary.nvim
[neodev.nvim]: https://github.com/folke/neodev.nvim
