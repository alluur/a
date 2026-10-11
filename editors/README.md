# Editor support for A

## Vim / Neovim
```sh
mkdir -p ~/.vim && cp -r editors/vim/* ~/.vim/          # Neovim: ~/.config/nvim/
```
Add to `~/.vimrc`:
```vim
syntax on
colorscheme a-dark        " optional dark theme made for A
```
Files ending in `.a` are detected automatically (syntax, `//` comments, 4-space indent).
The theme needs a true-colour terminal (`set termguicolors` is included).

## nano
```sh
mkdir -p ~/.nanorc.d && cp editors/nano/a.nanorc ~/.nanorc.d/
echo 'include "~/.nanorc.d/a.nanorc"' >> ~/.nanorc
```
nano themes are part of the syntax file: it uses the 16 terminal colours, so it follows your terminal palette.
