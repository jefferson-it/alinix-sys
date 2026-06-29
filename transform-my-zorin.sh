#!/usr/bin/env bash
# ==============================================================================
#   transform-my-zorin.sh
#   Transforma o Zorin OS (ou qualquer Ubuntu/Debian com GNOME) no Alinix.
#
#   Uso:
#     bash transform-my-zorin.sh            → pergunta o modo
#     bash transform-my-zorin.sh --user     → modo usuário (~/.local, sem root)
#     bash transform-my-zorin.sh --root     → modo global (/usr, requer sudo)
# ==============================================================================
set -euo pipefail

# ── Cores e logging ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error() { echo -e "${RED}[ERRO]${NC}  $1"; }
log_stage() {
    echo -e "\n${PURPLE}${BOLD}════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}  $1${NC}"
    echo -e "${PURPLE}${BOLD}════════════════════════════════════════════════${NC}\n"
}

# ── Localização do repositório ────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPS_DIR="$REPO_DIR/apps"

[[ -d "$APPS_DIR" ]] || { log_error "apps/ não encontrado em $REPO_DIR. Execute dentro do repositório Alinix-Deb."; exit 1; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${PURPLE}${BOLD}"
cat << 'EOF'
     _      _   _           _
    / \    | | (_)  _ __   (_) __  __
   / _ \   | | | | | '_ \  | | \ \/ /
  / ___ \  | | | | | | | | | |  >  <
 /_/   \_\ |_| |_| |_| |_| |_| /_/\_\
EOF
echo -e "${NC}"
echo -e "  ${BOLD}Transform My Zorin — Alinix UX no seu sistema${NC}"
echo -e "  ─────────────────────────────────────────────────"
echo

# ── Parse de argumentos ───────────────────────────────────────────────────────
MODE=""
for arg in "$@"; do
    case "$arg" in
        --user)   MODE="user"   ;;
        --root)   MODE="root"   ;;
        --global) MODE="root"   ;;   # alias legado
        -h|--help)
            echo "Uso: bash transform-my-zorin.sh [--user|--root]"
            echo ""
            echo "  (sem args)  Pergunta o modo interativamente"
            echo "  --user      Instala só para o usuário atual (~/.local)"
            echo "  --root      Instala para todos os usuários (/usr) — requer sudo"
            exit 0 ;;
        *) log_error "Opção desconhecida: $arg"; exit 1 ;;
    esac
done

# ── Escolha interativa ────────────────────────────────────────────────────────
if [[ -z "$MODE" ]]; then
    echo -e "  Onde deseja instalar o Alinix?"
    echo
    echo -e "  ${BOLD}1)${NC} Usuário  — só para você (~/.local), sem root"
    echo -e "  ${BOLD}2)${NC} Global   — para todos os usuários (/usr), requer sudo"
    echo
    while true; do
        read -rp "  Escolha [1/2]: " opt
        case "$opt" in
            1) MODE="user"; break ;;
            2) MODE="root"; break ;;
            *) log_warn "Digite 1 ou 2." ;;
        esac
    done
fi

# ── Definir prefixo e flags ───────────────────────────────────────────────────
if [[ "$MODE" == "root" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        log_error "Modo global requer root."
        echo -e "  Rode: ${BOLD}sudo bash transform-my-zorin.sh --root${NC}"
        exit 1
    fi
    PREFIX="/usr"
    EXT_PREFIX="/usr/share/gnome-shell/extensions"
    THEME_PREFIX="/usr/share/themes"
    ICONS_PREFIX="/usr/share/icons"
    MODE_FLAG="--root"
    IS_ROOT=1
else
    PREFIX="$HOME/.local"
    EXT_PREFIX="$HOME/.local/share/gnome-shell/extensions"
    THEME_PREFIX="$HOME/.local/share/themes"
    ICONS_PREFIX="$HOME/.local/share/icons"
    MODE_FLAG="--user"
    IS_ROOT=0
fi

log_ok "Modo: ${BOLD}$MODE${NC} → prefixo: $PREFIX"

# ==============================================================================
# STAGE 0: Verificar dependências
# ==============================================================================
log_stage "Stage 0 — Verificando dependências"

MISSING=()
need()    { command -v "$1" &>/dev/null && log_ok "$1" || { log_warn "Ausente: $1"; MISSING+=("${2:-$1}"); }; }
need_gi() {
    python3 -c "import gi; gi.require_version('$1','$2')" 2>/dev/null \
        && log_ok "python3·$1·$2" \
        || { log_warn "Ausente: python3·$1·$2"; MISSING+=("$3"); }
}

need python3
need git
need gsettings            "libglib2.0-bin"
need glib-compile-schemas "libglib2.0-dev-bin"
need update-desktop-database "desktop-file-utils"
need_gi Gtk  4.0   "gir1.2-gtk-4.0"
need_gi Adw  1     "gir1.2-adw-1"
need_gi Vte  3.91  "gir1.2-vte-3.91"

if (( IS_ROOT )); then
    need rsvg-convert  "librsvg2-bin"
    need mksquashfs    "squashfs-tools"
fi

python3 -c "import libtorrent" 2>/dev/null \
    && log_ok "python3-libtorrent" \
    || log_warn "python3-libtorrent ausente (opcional — Flavius Torrent)"

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo
    log_warn "Dependências ausentes: ${MISSING[*]}"
    if command -v apt-get &>/dev/null; then
        if (( IS_ROOT )); then
            log_info "Instalando automaticamente..."
            apt-get update -qq
            apt-get install -y "${MISSING[@]}" || log_warn "Alguns pacotes falharam — continuando."
        else
            echo -e "  Instale: ${BOLD}sudo apt install ${MISSING[*]}${NC}"
            read -rp "  Continuar mesmo assim? [s/N]: " cont
            [[ "$cont" =~ ^[sS]$ ]] || exit 1
        fi
    fi
fi

# ── Helper de execução de sub-scripts ────────────────────────────────────────
_run() {
    local label="$1" script="$2"
    shift 2
    if [[ ! -f "$script" ]]; then
        log_warn "$label: script não encontrado ($script)"
        return
    fi
    log_info "[$label] executando..."
    local out
    if out=$(bash "$script" "$@" 2>&1); then
        log_ok "[$label] concluído"
    else
        if echo "$out" | grep -qi "instalado\|ok\|sucesso"; then
            log_ok "[$label] concluído (com avisos)"
        else
            log_warn "[$label] FALHOU"
            echo "$out" | tail -5 | sed 's/^/    /'
        fi
    fi
}

# ==============================================================================
# STAGE 1: Extensões GNOME Shell
# ==============================================================================
log_stage "Stage 1 — Extensões GNOME Shell"

_run "ErasShell (shell principal)" "$APPS_DIR/erasshell/install-erasshell.sh"    $MODE_FLAG
_run "Alinix Dock (dock inferior)" "$APPS_DIR/alinix-dock/install.sh"            $MODE_FLAG
_run "Menu Global (barra de menu)" "$APPS_DIR/menu-global/install.sh"            $MODE_FLAG
_run "Wobbly Windows (animações)"  "$APPS_DIR/wobbly-windows/install.sh"         $MODE_FLAG

# ==============================================================================
# STAGE 2: Apps Desktop
# ==============================================================================
log_stage "Stage 2 — Apps Desktop"

_run "JExplorer (gerenciador de arquivos)" "$APPS_DIR/desktop/jexplorer/install.sh"  $MODE_FLAG
_run "JTerminal (terminal)"               "$APPS_DIR/desktop/jterminal/install.sh"   $MODE_FLAG
_run "Alí (lançador de apps)"             "$APPS_DIR/ali/install.sh"                 $MODE_FLAG
_run "QuickLook (pré-visualização)"       "$APPS_DIR/quicklook/install.sh"
_run "Alinix Settings"                    "$APPS_DIR/desktop/config-app/install.sh" $MODE_FLAG 2>/dev/null || true

# ==============================================================================
# STAGE 3: Tema GTK, ícones e cursor
# ==============================================================================
log_stage "Stage 3 — Tema, ícones e cursor"

# Tema GTK alinix-dracula
_run "Tema alinix-dracula" "$APPS_DIR/themes/alinix-dracula/install.sh" $MODE_FLAG

# Papirus icon theme (só disponível via apt no modo root)
if (( IS_ROOT )); then
    if ! dpkg -l papirus-icon-theme &>/dev/null 2>&1; then
        log_info "Instalando Papirus icon theme..."
        apt-get install -y --no-install-recommends papirus-icon-theme 2>/dev/null \
            && log_ok "Papirus instalado" \
            || log_warn "Papirus falhou"
    else
        log_ok "Papirus já instalado"
    fi
else
    log_warn "Papirus requer --root para instalar via apt"
fi

# GoogleDot-Black cursor
log_info "[cursor] instalando GoogleDot-Black..."
_googledot_dest="$ICONS_PREFIX"
mkdir -p "$_googledot_dest"
_gdot_tmp="$(mktemp -d)"
curl -fsSL "https://github.com/ful1e5/Google_Cursor/releases/latest/download/GoogleDot-Black.tar.gz" \
    -o "$_gdot_tmp/googledot.tar.gz" 2>/dev/null \
|| curl -fsSL "https://github.com/ful1e5/Google_Cursor/releases/download/v2.0.0/GoogleDot-Black.tar.gz" \
    -o "$_gdot_tmp/googledot.tar.gz" 2>/dev/null \
|| true
if [[ -f "$_gdot_tmp/googledot.tar.gz" ]]; then
    tar -xzf "$_gdot_tmp/googledot.tar.gz" -C "$_googledot_dest" 2>/dev/null && log_ok "[cursor] GoogleDot-Black instalado" || log_warn "[cursor] falha ao extrair"
else
    log_warn "[cursor] download falhou"
fi
rm -rf "$_gdot_tmp"

# ==============================================================================
# STAGE 4: ZSH + oh-my-zsh + fastfetch (modo root aplica ao skel)
# ==============================================================================
log_stage "Stage 4 — ZSH, oh-my-zsh e fastfetch"

SKEL_SRC="${REPO_DIR}/sys/skel"

if (( IS_ROOT )); then
    # ── Garantir ZSH instalado ───────────────────────────────────────────────
    if ! command -v zsh &>/dev/null; then
        log_info "Instalando ZSH..."
        apt-get install -y --no-install-recommends zsh bash bash-completion
    fi
    log_ok "ZSH disponível"

    # ── oh-my-zsh no /etc/skel ───────────────────────────────────────────────
    SKEL_DST="/etc/skel"
    OMZ_DST="${SKEL_DST}/.oh-my-zsh"

    if [[ -d "$SKEL_SRC" ]]; then
        cp -a "${SKEL_SRC}/"* "${SKEL_DST}/" 2>/dev/null || true
        cp -a "${SKEL_SRC}/".* "${SKEL_DST}/" 2>/dev/null || true
        log_ok "Skel copiado de sys/skel/"
    fi

    if [[ ! -d "$OMZ_DST" ]]; then
        log_info "Clonando oh-my-zsh..."
        git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DST"
    fi
    [[ ! -d "${OMZ_DST}/custom/plugins/zsh-autosuggestions" ]] && \
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "${OMZ_DST}/custom/plugins/zsh-autosuggestions" 2>/dev/null || true
    [[ ! -d "${OMZ_DST}/custom/plugins/zsh-syntax-highlighting" ]] && \
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "${OMZ_DST}/custom/plugins/zsh-syntax-highlighting" 2>/dev/null || true

    mkdir -p "${OMZ_DST}/custom/themes"
    [[ -f "${SKEL_SRC}/alinix.zsh-theme" ]] && \
        cp "${SKEL_SRC}/alinix.zsh-theme" "${OMZ_DST}/custom/themes/alinix.zsh-theme"

    # Mudar shell padrão do usuário atual e do root
    chsh -s /bin/zsh root 2>/dev/null || true
    [[ -n "${SUDO_USER:-}" ]] && chsh -s /bin/zsh "$SUDO_USER" 2>/dev/null || true
    sed -i 's|^DSHELL=.*|DSHELL=/bin/zsh|' /etc/adduser.conf 2>/dev/null || true
    log_ok "ZSH configurado como shell padrão"

    # fastfetch via PPA
    if ! command -v fastfetch &>/dev/null; then
        log_info "Instalando fastfetch..."
        add-apt-repository -y ppa:zhangsongcui3371/fastfetch 2>/dev/null || true
        apt-get update -qq 2>/dev/null || true
        apt-get install -y --no-install-recommends fastfetch 2>/dev/null \
            && log_ok "fastfetch instalado" || log_warn "fastfetch falhou"
    else
        log_ok "fastfetch já instalado"
    fi

    # Config fastfetch no skel
    mkdir -p "${SKEL_DST}/.config/fastfetch"
    [[ -f "${SKEL_SRC}/fastfetch-config.jsonc" ]] && \
        cp "${SKEL_SRC}/fastfetch-config.jsonc" "${SKEL_DST}/.config/fastfetch/config.jsonc"
    [[ -f "${SKEL_SRC}/alinix-ascii.txt" ]] && \
        cp "${SKEL_SRC}/alinix-ascii.txt" "${SKEL_DST}/.config/fastfetch/alinix-ascii.txt"

else
    # ── Modo usuário: só instalar OMZ para o usuário atual ───────────────────
    OMZ_DST="$HOME/.oh-my-zsh"
    if [[ ! -d "$OMZ_DST" ]]; then
        log_info "Clonando oh-my-zsh em $OMZ_DST..."
        git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DST"
    fi
    [[ ! -d "${OMZ_DST}/custom/plugins/zsh-autosuggestions" ]] && \
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "${OMZ_DST}/custom/plugins/zsh-autosuggestions" 2>/dev/null || true
    [[ ! -d "${OMZ_DST}/custom/plugins/zsh-syntax-highlighting" ]] && \
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "${OMZ_DST}/custom/plugins/zsh-syntax-highlighting" 2>/dev/null || true

    mkdir -p "${OMZ_DST}/custom/themes"
    [[ -f "${SKEL_SRC}/alinix.zsh-theme" ]] && \
        cp "${SKEL_SRC}/alinix.zsh-theme" "${OMZ_DST}/custom/themes/alinix.zsh-theme"

    # Copiar .zshrc se ainda não existe
    if [[ ! -f "$HOME/.zshrc" ]] && [[ -f "${SKEL_SRC}/../skel/.zshrc" ]]; then
        cp "${SKEL_SRC}/.zshrc" "$HOME/.zshrc"
    fi

    # Config fastfetch para o usuário
    mkdir -p "$HOME/.config/fastfetch"
    [[ -f "${SKEL_SRC}/fastfetch-config.jsonc" ]] && \
        cp "${SKEL_SRC}/fastfetch-config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    [[ -f "${SKEL_SRC}/alinix-ascii.txt" ]] && \
        cp "${SKEL_SRC}/alinix-ascii.txt" "$HOME/.config/fastfetch/alinix-ascii.txt"

    log_ok "oh-my-zsh instalado em $HOME"
    log_warn "Para mudar seu shell para ZSH: chsh -s /bin/zsh (requer root)"
fi

# ==============================================================================
# STAGE 5: Plymouth (apenas modo root)
# ==============================================================================
log_stage "Stage 5 — Tema Plymouth Alinix"

if (( IS_ROOT )); then
    _run "Plymouth alinix-theme" "${REPO_DIR}/sys/plymouth/install-plymouth.sh"
else
    log_warn "Plymouth requer --root para ser instalado"
fi

# ==============================================================================
# STAGE 6: Desktop UX (GSettings overrides, touchegg, variáveis de ambiente)
# ==============================================================================
log_stage "Stage 6 — Desktop UX"

_run "desktop-ux" "$REPO_DIR/sys/desktop-ux/install-desktop-ux.sh" $MODE_FLAG

# Wallpaper
WP_SRC="${REPO_DIR}/sys/assets/black-and-white-3840x2160-21293.jpg"
if [[ -f "$WP_SRC" ]]; then
    if (( IS_ROOT )); then
        mkdir -p "/usr/share/backgrounds/alinix"
        cp "$WP_SRC" "/usr/share/backgrounds/alinix/alinix-wallpaper-01.jpg"
        log_ok "Wallpaper instalado em /usr/share/backgrounds/alinix/"
    else
        mkdir -p "$HOME/.local/share/backgrounds/alinix"
        cp "$WP_SRC" "$HOME/.local/share/backgrounds/alinix/alinix-wallpaper-01.jpg"
        log_ok "Wallpaper instalado em ~/.local/share/backgrounds/alinix/"
    fi
fi

# Ícone/logo do sistema
LOGO_SRC="${REPO_DIR}/sys/assets/logo.svg"
if [[ -f "$LOGO_SRC" ]]; then
    if (( IS_ROOT )); then
        mkdir -p "/usr/share/icons/hicolor/scalable/apps" "/usr/share/pixmaps"
        cp "$LOGO_SRC" "/usr/share/icons/hicolor/scalable/apps/alinix-logo.svg"
        cp "$LOGO_SRC" "/usr/share/pixmaps/alinix-logo.svg"
    else
        mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"
        cp "$LOGO_SRC" "$HOME/.local/share/icons/hicolor/scalable/apps/alinix-logo.svg"
    fi
fi

# ==============================================================================
# STAGE 7: GSettings — aplicar configurações de desktop
# ==============================================================================
log_stage "Stage 7 — Aplicando configurações GNOME"

# Compilar schemas antes de aplicar GSettings
if (( IS_ROOT )); then
    glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null \
        && log_ok "Schemas compilados" || log_warn "glib-compile-schemas falhou"
fi

if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v gsettings &>/dev/null; then

    _gs() {
        gsettings set "$1" "$2" "$3" 2>/dev/null \
            && log_ok "$2 → $3" \
            || log_warn "Falha: gsettings set $1 $2 $3"
    }

    _gs org.gnome.desktop.wm.preferences    button-layout         'close,minimize,maximize:appmenu'
    _gs org.gnome.desktop.wm.preferences    theme                 'alinix-dracula'
    _gs org.gnome.desktop.interface         color-scheme          'prefer-dark'
    _gs org.gnome.desktop.interface         gtk-theme             'alinix-dracula'
    _gs org.gnome.desktop.interface         icon-theme            'Papirus-Dark'
    _gs org.gnome.desktop.interface         cursor-theme          'GoogleDot-Black'
    _gs org.gnome.desktop.interface         font-name             'Cantarell 11'
    _gs org.gnome.desktop.peripherals.touchpad natural-scroll      true
    _gs org.gnome.desktop.peripherals.touchpad tap-to-click        true
    _gs org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
    _gs org.gnome.mutter                    dynamic-workspaces    true
    _gs org.gnome.desktop.input-sources     xkb-options           "['altwin:ctrl_win']"

    # Wallpaper
    _WP_PATH=""
    if (( IS_ROOT )); then
        _WP_PATH="file:///usr/share/backgrounds/alinix/alinix-wallpaper-01.jpg"
    elif [[ -f "$HOME/.local/share/backgrounds/alinix/alinix-wallpaper-01.jpg" ]]; then
        _WP_PATH="file://$HOME/.local/share/backgrounds/alinix/alinix-wallpaper-01.jpg"
    fi
    if [[ -n "$_WP_PATH" ]]; then
        _gs org.gnome.desktop.background picture-uri           "$_WP_PATH"
        _gs org.gnome.desktop.background picture-uri-dark      "$_WP_PATH"
        _gs org.gnome.desktop.background picture-options       'zoom'
        _gs org.gnome.desktop.background primary-color         '#0d001a'
    fi

    # Extensões — só habilita as que estão instaladas para evitar tela preta
    _ext_list=()
    _ext_check() {
        local uuid="$1"
        local found=false
        for dir in /usr/share/gnome-shell/extensions "$HOME/.local/share/gnome-shell/extensions"; do
            [[ -f "$dir/$uuid/metadata.json" ]] && found=true && break
        done
        if $found; then
            _ext_list+=("$uuid")
            log_ok "Extensão encontrada: $uuid"
        else
            log_warn "Extensão não encontrada (ignorada): $uuid"
        fi
    }
    _ext_check 'user-theme@gnome-shell-extensions.gcampax.github.com'
    _ext_check 'erasshell@alinix'
    _ext_check 'alinix-dock@alinix.osx'
    _ext_check 'menu-global@alinix.osx'
    _ext_check 'wobbly-windows@weinberg.org'

    if [[ ${#_ext_list[@]} -gt 0 ]]; then
        # Monta a string de lista GSettings
        _ext_gs="["
        for i in "${!_ext_list[@]}"; do
            [[ $i -gt 0 ]] && _ext_gs+=","
            _ext_gs+="'${_ext_list[$i]}'"
        done
        _ext_gs+="]"
        _gs org.gnome.shell enabled-extensions "$_ext_gs"
    fi

    # Tema de shell
    _gs org.gnome.shell.extensions.user-theme name 'alinix-dracula'

    # Apps favoritos no dock
    _gs org.gnome.shell favorite-apps \
        "['firefox.desktop','jexplorer.desktop','jterminal.desktop','com.alinix.ali.desktop','alinix-settings.desktop','org.gnome.TextEditor.desktop']"

    # Ícones gtk4 (update-icon-cache)
    if (( IS_ROOT )); then
        gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
    else
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true

else
    log_warn "Sem sessão GNOME ativa — GSettings não aplicados. Relogue e execute novamente."
fi

# ==============================================================================
# STAGE 7.5: Script de recuperação de emergência (tela preta)
# ==============================================================================
log_stage "Stage 7.5 — Criando script de recuperação de emergência"

if (( IS_ROOT )); then
    cat > /usr/local/bin/alinix-recover << 'RECOVER_EOF'
#!/usr/bin/env bash
# Recupera o GNOME de tela preta causada por extensões Alinix.
# Execute via TTY (Ctrl+Alt+F3) como o usuário normal (sem sudo).
echo "=== Alinix Recovery ==="
echo "Desabilitando extensões Alinix temporariamente..."
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
gsettings set org.gnome.shell enabled-extensions "['user-theme@gnome-shell-extensions.gcampax.github.com']"
gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>']"
echo "Reiniciando GNOME Shell..."
DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 gnome-shell --replace &>/dev/null &
sleep 3
echo ""
echo "Pronto. Volte à sessão gráfica com Ctrl+Alt+F2 ou Ctrl+Alt+F1."
echo "Para reativar extensões depois: bash ~/Desktop/projects/Alinix-Deb/transform-my-zorin.sh --user"
RECOVER_EOF
    chmod +x /usr/local/bin/alinix-recover
    log_ok "Script de recuperação criado: /usr/local/bin/alinix-recover"
    log_info "Se travar em tela preta: Ctrl+Alt+F3 → login → 'alinix-recover'"
else
    _recover_dir="$HOME/.local/bin"
    mkdir -p "$_recover_dir"
    cat > "$_recover_dir/alinix-recover" << 'RECOVER_EOF'
#!/usr/bin/env bash
echo "=== Alinix Recovery ==="
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
gsettings set org.gnome.shell enabled-extensions "['user-theme@gnome-shell-extensions.gcampax.github.com']"
gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>']"
echo "Reiniciando GNOME Shell..."
DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 gnome-shell --replace &>/dev/null &
sleep 3
echo "Pronto. Ctrl+Alt+F2 para voltar."
RECOVER_EOF
    chmod +x "$_recover_dir/alinix-recover"
    log_ok "Script de recuperação criado: $_recover_dir/alinix-recover"
    log_info "Se travar em tela preta: Ctrl+Alt+F3 → login → '~/.local/bin/alinix-recover'"
fi

# ==============================================================================
# STAGE 8: Atalho Super tap → Alí (xcape)
# ==============================================================================
log_stage "Stage 8 — Atalho Super tap → Alí"

if command -v xcape &>/dev/null && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    gsettings set org.gnome.mutter overlay-key '' 2>/dev/null || true
    pkill -f "xcape.*F12" 2>/dev/null || true
    xcape -e 'Super_L=ctrl|alt|shift|F12' &
    log_ok "xcape configurado (Super tap → Alí)"

    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/alinix-xcape.desktop" << 'DESK'
[Desktop Entry]
Type=Application
Name=Alinix Super Key
Exec=xcape -e 'Super_L=ctrl|alt|shift|F12'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESK
    log_ok "Autostart do xcape criado"
else
    log_warn "xcape não encontrado — instale: sudo apt install xcape"
    log_warn "Depois: xcape -e 'Super_L=ctrl|alt|shift|F12'"
fi

# ==============================================================================
# Resumo final
# ==============================================================================
echo
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Alinix — transformação concluída! ($PREFIX)${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
echo
echo -e "  ${BOLD}Próximos passos:${NC}"
echo -e "    1. Pressione ${BOLD}Alt+F2${NC} e digite ${BOLD}r${NC} para reiniciar o GNOME Shell"
echo -e "       (ou faça logout/login se estiver em Wayland)"
if ! command -v zsh &>/dev/null; then
    echo -e "    2. Instale o ZSH: ${BOLD}sudo apt install zsh${NC}"
    echo -e "       Em seguida: ${BOLD}chsh -s /bin/zsh${NC}"
fi
echo
echo -e "  ${BOLD}Apps disponíveis:${NC}"
echo -e "    ali          → lançador de apps (Super tap)"
echo -e "    jexplorer    → gerenciador de arquivos"
echo -e "    jterminal    → terminal"
echo -e "    quicklook    → pré-visualização de arquivos"
echo
echo -e "  ${BOLD}Extensões ativas:${NC}"
echo -e "    ErasShell  •  Alinix Dock  •  Menu Global  •  Wobbly Windows"
echo
