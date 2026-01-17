# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Disable oh-my-zsh theme (using starship instead)
ZSH_THEME=""

# Plugins
plugins=(
    git
    zsh-autosuggestions
    F-Sy-H
)

# Add custom completions to fpath (gnmic, gnoic, etc.)
fpath=(~/.oh-my-zsh/completions $fpath)

source $ZSH/oh-my-zsh.sh

# Initialize starship prompt
eval "$(starship init zsh)"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
