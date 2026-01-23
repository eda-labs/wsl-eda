# Source system-wide proxy settings if present
[[ -f /etc/profile.d/custom_export.sh ]] && source /etc/profile.d/custom_export.sh

# EDA playground tools and local binaries (must be set before oh-my-zsh for completions)
export PATH="$HOME/playground/tools:$HOME/.local/bin:$PATH"

# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Disable oh-my-zsh theme (using starship instead)
ZSH_THEME=""

# Custom completions path (must be set before sourcing oh-my-zsh)
fpath=(~/.zsh/completions $fpath)

# Plugins
plugins=(
    git
    kubectl
    ssh
    zsh-autosuggestions
    F-Sy-H
)

source $ZSH/oh-my-zsh.sh

# Initialize starship prompt
eval "$(starship init zsh)"

# k9s configuration
export K9S_SKIN="dracula"

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Source edactl completion
[[ -f ~/.zsh/completions/edactl_completion.zsh ]] && source ~/.zsh/completions/edactl_completion.zsh
