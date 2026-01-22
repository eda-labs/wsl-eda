# Source system-wide proxy settings if present
[[ -f /etc/profile.d/custom_export.sh ]] && source /etc/profile.d/custom_export.sh

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

source $ZSH/oh-my-zsh.sh

# Initialize starship prompt
eval "$(starship init zsh)"

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
