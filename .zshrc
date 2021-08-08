# -*- mode: sh -*-
# vim: set ft=sh :

# source Prezto
ZSHRC="${ZDOTDIR:-$HOME}/.zprezto/runcoms/zshrc"
[[ -s "${ZSHRC}" ]] && source "${ZSHRC}"

# load zsh flagments
ZSH_D="${ZDOTDIR:-$HOME}/.zsh.d"
mkdir -p "${ZSH_D}"
for f in "${ZSH_D}/"*
do
  source $f
done
