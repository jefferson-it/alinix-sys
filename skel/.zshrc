# ╔══════════════════════════════════════════════════════════════╗
# ║           Alinix Linux - Configuração do ZSH               ║
# ╚══════════════════════════════════════════════════════════════╝

# Caminho para a instalação do oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"

# Tema personalizado do Alinix
ZSH_THEME="alinix"

# No Alinix, $HOME mapeia para /Users/$USER via bind mount /home -> /Users
# O export é feito globalmente em /etc/profile.d/alinix-home.sh

# ── Plugins ──────────────────────────────────────────────────
# git:                      atalhos e informações do git
# sudo:                     pressione ESC duas vezes para adicionar sudo
# zsh-autosuggestions:      sugestões automáticas baseadas no histórico
# zsh-syntax-highlighting:  destaque de sintaxe em tempo real
plugins=(
    git
    sudo
    zsh-autosuggestions
    zsh-syntax-highlighting
)

# Carrega o oh-my-zsh (se instalado)
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
    source "$ZSH/oh-my-zsh.sh"
fi

# ── Aliases ──────────────────────────────────────────────────
# Atalhos personalizados do Alinix
alias c='clear'
alias desk='cd ~/Desktop'
alias doc='cd ~/Documentos'

# Aliases úteis adicionais
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# ── Histórico ────────────────────────────────────────────────
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

# ── Fastfetch ────────────────────────────────────────────────
# Exibe informações do sistema ao iniciar o terminal
# Só executa se for um shell interativo e não estiver dentro de outro programa
if [[ $- == *i* ]] && [[ -z "$INSIDE_EMACS" ]] && [[ -z "$VSCODE_PID" ]] && [[ -z "$TERM_PROGRAM_VERSION" ]] && [[ $(tty) != "not a tty" ]]; then
    if command -v fastfetch &> /dev/null; then
        fastfetch --config ~/.config/fastfetch/config.jsonc 2>/dev/null || fastfetch
    fi
fi
