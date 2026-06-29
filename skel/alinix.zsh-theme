# ╔══════════════════════════════════════════════════════════════╗
# ║        Alinix ZSH Theme - Tema personalizado do Alinix     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Local:  LOGO dirname >              (dentro de git: LOGO dirname branch >)
# SSH:    user@host 🔐 dirname >      (dentro de git: user@host 🔐 dirname branch >)
# Direito: hora
#
# O logo usa U+E000 (Private Use Area) da fonte AlinixLogo,
# que renderiza a logo do Alinix (cacho de uvas).
# ==============================================================================

# ── Cores (tabela do oh-my-zsh) ──────────────────────────────
local purple="%{$FG[141]%}"
local green="%{$FG[114]%}"
local cyan="%{$FG[081]%}"
local yellow="%{$FG[221]%}"
local red="%{$FG[196]%}"
local orange="%{$FG[208]%}"
local reset="%{$reset_color%}"
local bold="%{$terminfo[bold]%}"

# ── Logo Alinix (fonte especial: U+E000) ─────────────────────
local logo=$'\ue000'

# ── Detecta SSH ──────────────────────────────────────────────
local alinix_ssh=""
if [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" || -n "$SSH_CONNECTION" ]]; then
    alinix_ssh="${purple}%n${reset}@${cyan}%m${reset} 🔐 "
fi

# ── Informação do git (branch) ───────────────────────────────
function alinix_git_info() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -n "$branch" ]]; then
        echo "${green} ${branch}${reset}"
    fi
}

# ── Pasta atual (só o último componente, home vira ~) ────────
function alinix_dir() {
    local dir="${PWD/#$HOME/~}"
    echo "${dir##*/}"
}

# ── Monta o prompt ───────────────────────────────────────────
setopt PROMPT_SUBST

PROMPT='${alinix_ssh}${bold}${purple}${logo} $(alinix_dir)${reset}$(alinix_git_info) ${purple}>${reset} '
RPROMPT='${purple}%T${reset}'
