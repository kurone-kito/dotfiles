-- Editor options (migrated from vimrc with NeoVim-specific additions)
local opt = vim.opt

-- Appearance
opt.background = "dark"
opt.cursorline = true
opt.number = true
opt.signcolumn = "yes"
opt.termguicolors = true
opt.title = true
opt.showmode = false -- shown by statusline instead

-- Encoding (utf-8 is default in NeoVim; fileencodings still useful)
opt.fileencodings = { "utf-8", "sjis", "cp932", "euc-jp", "iso-2022-jp" }
opt.fileformats = { "unix", "dos", "mac" }

-- Indentation
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true

-- Search
opt.gdefault = true
opt.ignorecase = true
opt.smartcase = true

-- Editing
opt.backspace = { "indent", "eol", "start" }
opt.clipboard = "unnamedplus"
opt.showmatch = true
opt.modeline = true
opt.modelines = 4
opt.exrc = true

-- Files
opt.undofile = true
opt.swapfile = false
opt.backup = false

-- Completion
opt.completeopt = { "menu", "menuone", "noselect" }

-- Splits
opt.splitbelow = true
opt.splitright = true

-- Scroll
opt.scrolloff = 8
opt.sidescrolloff = 8
