export ZSH=/usr/local/share/oh-my-zsh
export ZSH_CUSTOM=$ZSH/custom

ZSH_THEME="robbyrussell"
plugins=(git autojump zsh-autosuggestions zsh-syntax-highlighting)

DISABLE_MAGIC_FUNCTIONS="true"
zstyle ':omz:update' mode disabled

source "$ZSH/oh-my-zsh.sh"

eval "$(mise activate zsh)"
