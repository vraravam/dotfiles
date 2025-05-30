" file location: ${HOME}/.vimrc

set nocompatible              " be iMproved, required
" filetype off                  " required

" mouse navigation
set mouse=a

set title
" highlighting
" set relativenumber
set number
set ruler
syntax on
set background=dark
set cursorline
set incsearch
set hlsearch
set ignorecase
set smartcase
set showmatch
:highlight search guifg=yellow guibg=darkred

" Status bar
set laststatus=2

" Intent width
set shiftwidth=2

" tabbing
set list listchars=nbsp:¬,tab:»·,trail:·,extends:>
set expandtab
set smarttab
set smartindent
set shiftwidth=2
set tabstop=2
set softtabstop=2
set bs=2

set undofile
set undodir=/tmp

set nobackup
" https://en.parceljs.org/hmr.html#safe-write
set backupcopy=yes

" Auto text wrapping
set wrap

set encoding=utf-8

" Turned off "ignore whitespace during diffing" since I need to test this out first whether it impacts my git diffs
" set diffopt+=iwhite " Ignore whitespace whilst diffing
" nnoremap <silent> <F5> :let _s=@/<Bar>:%s/\s\+$//e<Bar>:let @/=_s<Bar>:nohl<CR>

" have command-line completion <Tab> (for filenames, help topics, option
" names) first list the available options and complete the longest common part,
" then have further <Tab>s cycle through the possibilities:
set wildmode=list:longest,full
set wildmenu

" folding settings
set foldmethod=indent
set foldnestmax=10
set nofoldenable
set foldlevel=1

" All of your Plugins must be added before the following line
filetype plugin indent on    " required

let g:solarized_termcolors=256

" Strip trailing whitespace
function! <SID>StripTrailingWhitespaces()
  " Preparation: save last search, and cursor position.
  let _s=@/
  let l = line(".")
  let c = col(".")
  " Do the business:
  %s/\s\+$//e
  " Clean up: restore previous search history, and cursor position
  let @/=_s
  call cursor(l, c)
endfunction
autocmd BufWritePre * :call <SID>StripTrailingWhitespaces()

set history=500
set autoindent
highlight Search term=bold cterm=bold ctermfg=black ctermbg=green gui=bold guifg=black guibg=green
highlight ExtraWhitespace ctermbg=LightBlue
