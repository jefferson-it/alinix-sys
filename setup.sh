#!/usr/bin/env bash
# ==============================================================================
#   Alinix — setup.sh
#   Script principal de construção da ISO do Alinix-Deb
#
#   Usa debootstrap do Ubuntu Noble (24.04) minimal como base.
#   Instala apenas os componentes solicitados (não todo o GNOME).
#   Aplica a hierarquia Alinix FHS, tema Plymouth, ZSH + oh-my-zsh,
#   permissões (appmgr), drivers de vídeo, e o modo live com Casper.
#
#   Uso:
#     sudo ./setup.sh              → build completo (ISO)
#     sudo ./setup.sh --chroot     → apenas monta e entra no chroot
#     sudo ./setup.sh --iso-only   → gera ISO de um build existente
#     sudo ./setup.sh --clean      → limpa tudo e recomeça
#
#   Requisitos do host:
#     debootstrap, squashfs-tools, xorriso, grub-pc-bin,
#     grub-efi-amd64-bin, mtools, librsvg2-bin
# ==============================================================================
set -euo pipefail

# ── Build log ─────────────────────────────────────────────────────────────────
BUILD_LOG="/var/tmp/alinix-build/build.log"
mkdir -p "$(dirname "$BUILD_LOG")"
exec > >(tee -a "$BUILD_LOG") 2>&1
echo "========== Build iniciado: $(date) =========="

# ── Cores e logging ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error()   { echo -e "${RED}[ERRO]${NC}  $1"; }
log_stage()   { echo -e "\n${PURPLE}${BOLD}════════════════════════════════════════════════${NC}"; \
                echo -e "${PURPLE}${BOLD}  $1${NC}"; \
                echo -e "${PURPLE}${BOLD}════════════════════════════════════════════════${NC}\n"; }

# ── Configuração ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Build root fora de /home para evitar problemas com noexec/nodev
BUILD_ROOT="/var/tmp/alinix-build/alinix-root"
DIST_DIR="${SCRIPT_DIR}/sys/dist"
ISO_OUT="${DIST_DIR}/alinix.iso"
CODENAME="noble"   # Ubuntu 24.04
ARCH="amd64"
MIRROR="http://archive.ubuntu.com/ubuntu"

# ── Help rápido (antes do check de root) ─────────────────────────────────────
for _a in "$@"; do
    if [[ "$_a" == "-h" || "$_a" == "--help" ]]; then
        echo "Uso: sudo ./setup.sh [OPÇÕES]"
        echo ""
        echo "  (sem args)           Build completo: debootstrap + config + ISO"
        echo "  --initrd             Recompila o alinix-init e regenera o initramfs"
        echo "  --iso                Regenera apenas a ISO (recompila init automaticamente)"
        echo "  --initrd --iso       Recompila init + regera ISO sem refazer o chroot"
        echo "  --fixup              Remove snapd, desativa casper-md5check, força X11 no GDM + regera ISO"
        echo "  --chroot             Monta e entra no chroot interativo"
        echo "  --clean              Remove build anterior e recomeça do zero"
        echo ""
        echo "  Seleção de kernel (combinável com --iso):"
        echo "  --lix7               Kernel-Lix 7.x binário existente (padrão)"
        echo "  --lix6               Kernel-Lix 6.x binário existente"
        echo "  --generic            Kernel genérico (linux-image-generic)"
        echo "  --recompile-kernel   Força recompilação do kernel selecionado"
        echo ""
        echo "  Exemplos:"
        echo "    sudo ./setup.sh --initrd --iso --lix7"
        echo "    sudo ./setup.sh --iso --lix6"
        echo "    sudo ./setup.sh --recompile-kernel --lix7 --iso"
        exit 0
    fi
done

# ── Verificação root ─────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    log_error "Este script precisa ser executado como root: sudo ./setup.sh"
    exit 1
fi

# Adicionar o diretório de binários de cargo do usuário sudo ao PATH (priorizando sobre o do host)
if [[ -n "${SUDO_USER:-}" ]]; then
    export PATH="/home/${SUDO_USER}/.cargo/bin:$PATH"
fi

# ── Parse de argumentos ──────────────────────────────────────────────────────
MODE="full"
OPT_INITRD=0
OPT_ISO=0
OPT_FIXUP=0
OPT_RECOMPILE_KERNEL=0

# Detectar se kernel foi especificado via flag antes de consumir os args
_KERNEL_FROM_FLAG=0
for _a in "$@"; do
    [[ "$_a" == "--lix6" || "$_a" == "--lix7" || "$_a" == "--generic" ]] && _KERNEL_FROM_FLAG=1
done

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chroot)            MODE="chroot";    shift ;;
        --iso-only|--iso)    MODE="iso-only"; OPT_ISO=1; shift ;;
        --initrd)            OPT_INITRD=1;   shift ;;
        --fixup)             MODE="iso-only"; OPT_FIXUP=1; OPT_ISO=1; OPT_INITRD=1; shift ;;
        --clean)             MODE="clean";   shift ;;
        --lix6)              KERNEL_MODE="lix6"; shift ;;
        --lix7)              KERNEL_MODE="lix7"; shift ;;
        --generic)           KERNEL_MODE="generic"; shift ;;
        --recompile-kernel)  OPT_RECOMPILE_KERNEL=1; shift ;;
        -h|--help)
            echo "Uso: sudo ./setup.sh [OPÇÕES]"
            echo ""
            echo "  (sem args)           Build completo: debootstrap + config + ISO"
            echo "  --initrd             Recompila o alinix-init e regera o initramfs"
            echo "  --iso                Regenera apenas a ISO (recompila init automaticamente)"
            echo "  --initrd --iso       Recompila init + regera ISO sem refazer o chroot"
            echo "  --chroot             Monta e entra no chroot interativo"
            echo "  --clean              Remove build anterior e recomeça do zero"
            echo ""
            echo "  Seleção de kernel (combinável com --iso):"
            echo "  --lix7               Kernel-Lix 7.x binário existente (padrão)"
            echo "  --lix6               Kernel-Lix 6.x binário existente"
            echo "  --generic            Kernel genérico (linux-image-generic)"
            echo "  --recompile-kernel   Força recompilação do kernel selecionado"
            echo ""
            echo "  Exemplos:"
            echo "    sudo ./setup.sh --initrd --iso --lix7"
            echo "    sudo ./setup.sh --iso --lix6"
            echo "    sudo ./setup.sh --recompile-kernel --lix7 --iso"
            exit 0 ;;
        *) log_error "Opção desconhecida: $1"; exit 1 ;;
    esac
done

# --iso sozinho implica --initrd (sempre recompila o init ao gerar ISO)
[[ "$OPT_ISO" -eq 1 ]] && OPT_INITRD=1

# ── Seleção de kernel ────────────────────────────────────────────────────────
# KERNEL_MODE: "lix6" | "lix7" | "generic"
# RECOMPILE_KERNEL: "y" | "n"
KERNEL_MODE="lix7"
RECOMPILE_KERNEL="n"

LIX_DIR="/home/jefferson/Desktop/projects/Kernel-Lix"
LIX_DIST="${LIX_DIR}/dist"
LIX6_SRC="${LIX_DIR}/linux-6.18.10"
LIX7_SRC="${LIX_DIR}/linux-7.1.2"

if [[ "$MODE" == "full" && "$OPT_RECOMPILE_KERNEL" -eq 1 ]]; then
    RECOMPILE_KERNEL="y"
fi

# Mostrar menu interativo apenas no build completo e quando kernel não foi
# especificado via flag (--lix6/--lix7/--generic).
# _KERNEL_FROM_FLAG é setado antes do parse consumir os args.
if [[ "$MODE" == "full" && "$_KERNEL_FROM_FLAG" -eq 0 ]]; then
    if [ -t 0 ] || [ -n "${SUDO_USER:-}" ]; then
        echo -e "\n${YELLOW}${BOLD}Escolha o kernel para a ISO Alinix:${NC}"
        echo -e "  1) Kernel-Lix 6.x  — usar binário existente"
        echo -e "  2) Kernel-Lix 6.x  — recompilar agora        (15-45 min)"
        echo -e "  3) Kernel-Lix 7.x  — usar binário existente  (Padrão)"
        echo -e "  4) Kernel-Lix 7.x  — recompilar agora        (15-45 min)"
        echo -e "  5) Kernel genérico — instalar via apt (linux-image-generic)"
        read -rp "Opção [1-5, padrão 3]: " _opt_k </dev/tty || _opt_k="3"
        case "${_opt_k:-3}" in
            1) KERNEL_MODE="lix6"; RECOMPILE_KERNEL="n" ;;
            2) KERNEL_MODE="lix6"; RECOMPILE_KERNEL="y" ;;
            4) KERNEL_MODE="lix7"; RECOMPILE_KERNEL="y" ;;
            5) KERNEL_MODE="generic"; RECOMPILE_KERNEL="n" ;;
            *) KERNEL_MODE="lix7"; RECOMPILE_KERNEL="n" ;;
        esac
    fi
fi

# Forçar compilação se não houver artefato em dist/ nem bzImage na árvore
if [[ "$KERNEL_MODE" == "lix6" && "$RECOMPILE_KERNEL" == "n" ]]; then
    if ! find "${LIX_DIST}" -maxdepth 1 -name "vmlinuz-6*-lix" 2>/dev/null | grep -q .; then
        if [[ ! -f "${LIX6_SRC}/arch/x86/boot/bzImage" ]]; then
            log_warn "Nenhum artefato Lix 6.x encontrado em dist/ — forçando compilação..."
            RECOMPILE_KERNEL="y"
        fi
    fi
fi
if [[ "$KERNEL_MODE" == "lix7" && "$RECOMPILE_KERNEL" == "n" ]]; then
    if ! find "${LIX_DIST}" -maxdepth 1 -name "vmlinuz-7*-lix" 2>/dev/null | grep -q .; then
        if [[ ! -f "${LIX7_SRC}/arch/x86/boot/bzImage" ]]; then
            log_warn "Nenhum artefato Lix 7.x encontrado em dist/ — forçando compilação..."
            RECOMPILE_KERNEL="y"
        fi
    fi
fi

compile_kernel() {
    local ksrc="$1"   # caminho da árvore do kernel
    local label="$2"  # "6.x" ou "7.x"
    log_stage "Compilando Kernel-Lix ${label}"
    log_info "Fonte: $ksrc"
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" env PATH="$PATH" HOME="/home/$SUDO_USER" \
            bash "${LIX_DIR}/build.sh" build --src "$ksrc"
    else
        bash "${LIX_DIR}/build.sh" build --src "$ksrc"
    fi
}

# ── Limpar build anterior ────────────────────────────────────────────────────
if [[ "$MODE" == "clean" ]]; then
    log_stage "Limpando build anterior"
    # Desmonta tudo que pode estar montado
    for mnt in proc sys dev/pts dev run; do
        umount -lf "${BUILD_ROOT}/${mnt}" 2>/dev/null || true
    done
    rm -rf "$BUILD_ROOT"
    log_ok "Build removido: $BUILD_ROOT"
    exit 0
fi

# ==============================================================================
# STAGE 0: Verificar dependências do host
# ==============================================================================
verify_host_deps() {
    log_stage "Stage 0 — Verificando dependências do host"

    local missing=()
    for cmd in debootstrap mksquashfs xorriso grub-mkrescue rsvg-convert busybox cpio gzip; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
            log_warn "Ausente: $cmd"
        else
            log_ok "$cmd"
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Instalando dependências faltantes..."
        apt-get update -qq
        apt-get install -y debootstrap squashfs-tools xorriso \
            grub-pc-bin grub-efi-amd64-bin grub2-common mtools \
            librsvg2-bin cpio gzip busybox-static util-linux
    fi

    log_ok "Todas dependências do host verificadas."
}

# ==============================================================================
# STAGE 1: Debootstrap — Sistema base minimal
# ==============================================================================
stage_debootstrap() {
    log_stage "Stage 1 — Debootstrap Ubuntu Noble Minimal"

    if [[ -d "$BUILD_ROOT/usr" ]]; then
        log_warn "Build existente encontrado em $BUILD_ROOT"
        log_info "Use --clean primeiro se quiser recomeçar."
        return 0
    fi

    mkdir -p "$BUILD_ROOT" "$DIST_DIR"

    debootstrap \
        --arch="$ARCH" \
        --variant=minbase \
        --include=apt,apt-utils,locales,sudo,systemd,systemd-sysv,dbus,udev \
        "$CODENAME" "$BUILD_ROOT" "$MIRROR"

    log_ok "Debootstrap concluído."
}

# ==============================================================================
# STAGE 2: Montar filesystems para chroot
# ==============================================================================
mount_chroot() {
    log_stage "Stage 2 — Montando filesystems para chroot"

    mount --bind /dev  "${BUILD_ROOT}/dev"  2>/dev/null || true
    mount --bind /dev/pts "${BUILD_ROOT}/dev/pts" 2>/dev/null || true
    mount -t proc proc "${BUILD_ROOT}/proc" 2>/dev/null || true
    mount -t sysfs sys "${BUILD_ROOT}/sys"  2>/dev/null || true
    mount -t tmpfs run "${BUILD_ROOT}/run"  2>/dev/null || true

    # Copiar resolv.conf para ter rede dentro do chroot
    cp /etc/resolv.conf "${BUILD_ROOT}/etc/resolv.conf" 2>/dev/null || true

    log_ok "Filesystems montados."
}

umount_chroot() {
    log_info "Desmontando filesystems do chroot..."
    for mnt in run sys proc dev/pts dev; do
        umount -lf "${BUILD_ROOT}/${mnt}" 2>/dev/null || true
    done
}

# ==============================================================================
# STAGE 3: Configuração do sistema dentro do chroot
# ==============================================================================
stage_configure_system() {
    log_stage "Stage 3 — Configurando sistema base dentro do chroot"

    # ── 3.1 Repositórios ─────────────────────────────────────────────────────
    cat > "${BUILD_ROOT}/etc/apt/sources.list" << EOF
deb ${MIRROR} ${CODENAME} main restricted universe multiverse
deb ${MIRROR} ${CODENAME}-updates main restricted universe multiverse
deb ${MIRROR} ${CODENAME}-security main restricted universe multiverse
EOF

    # ── 3.2 Hostname e hosts ─────────────────────────────────────────────────
    echo "alinix" > "${BUILD_ROOT}/etc/hostname"
    cat > "${BUILD_ROOT}/etc/hosts" << 'EOF'
127.0.0.1   localhost
127.0.1.1   alinix
::1         localhost ip6-localhost ip6-loopback
EOF

    # ── 3.2.1 DNS fixo na ISO (evita falha de resolução no live boot) ─────────
    # O systemd-resolved não está ativo no live, então forçamos DNS do Google.
    # O NetworkManager pode sobrescrever depois se o usuário configurar rede.
    cat > "${BUILD_ROOT}/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
    # Desabilitar symlink do systemd-resolved se existir
    rm -f "${BUILD_ROOT}/etc/resolv.conf" 2>/dev/null || true
    cat > "${BUILD_ROOT}/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

    # ── 3.3 Locale ───────────────────────────────────────────────────────────
    chroot "$BUILD_ROOT" /bin/bash -c "
        locale-gen en_US.UTF-8 pt_BR.UTF-8
        update-locale LANG=pt_BR.UTF-8
    "

    # ── 3.4 Timezone ─────────────────────────────────────────────────────────
    chroot "$BUILD_ROOT" /bin/bash -c "
        ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
        echo 'America/Sao_Paulo' > /etc/timezone
    "

    # ── 3.5 OS Release (Alinix branding) ───────────────────────────────────────
    cat > "${BUILD_ROOT}/etc/os-release" << 'EOF'
NAME="Alinix"
ID=alinix
ID_LIKE=ubuntu
PRETTY_NAME="Alinix 1.0"
VERSION_ID="1.0"
VERSION_CODENAME=onyx
VERSION="1.0 (Onyx)"
HOME_URL="https://alinix.org"
SUPPORT_URL="https://alinix.org/support"
BUG_REPORT_URL="https://github.com/anomalyco/alinix/issues"
EOF
    cat > "${BUILD_ROOT}/etc/lsb-release" << 'EOF'
DISTRIB_ID=Alinix
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=onyx
DISTRIB_DESCRIPTION="Alinix 1.0"
EOF

    # ── Branding TTY: remover textos Ubuntu do login ──────────────────────────
    # /etc/issue — mostrado antes do login (getty)
    cat > "${BUILD_ROOT}/etc/issue" << 'EOF'
Alinix 1.0 \n \l

EOF
    cat > "${BUILD_ROOT}/etc/issue.net" << 'EOF'
Alinix 1.0
EOF

    # /etc/motd — mostrado após o login (limpar completamente)
    truncate -s 0 "${BUILD_ROOT}/etc/motd" 2>/dev/null || true

    # Desabilitar motd-news e update-motd (sources de texto Ubuntu no TTY)
    chmod -x "${BUILD_ROOT}/etc/update-motd.d/"* 2>/dev/null || true
    # Substituir o 00-header para mostrar apenas o branding Alinix
    mkdir -p "${BUILD_ROOT}/etc/update-motd.d"
    cat > "${BUILD_ROOT}/etc/update-motd.d/00-alinix-header" << 'MOTD'
#!/bin/sh
printf '\nBem-vindo ao Alinix 1.0 (GNU/Linux %s %s)\n\n' "$(uname -r)" "$(uname -m)"
MOTD
    chmod +x "${BUILD_ROOT}/etc/update-motd.d/00-alinix-header"

    log_ok "Sistema base configurado."
}

# ==============================================================================
# STAGE 4: Instalar pacotes pré-definidos (NÃO todo o GNOME)
# ==============================================================================
stage_install_packages() {
    log_stage "Stage 4 — Instalando pacotes selecionados"

    # Usar heredoc com aspas simples ('CHROOT') para evitar problemas de escape
    # com aspas duplas dentro do script do chroot (ex: echo "deb [signed-by=...]")
    chroot "$BUILD_ROOT" /bin/bash <<'CHROOT'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq

# ── Shell ────────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends zsh bash bash-completion

# ── Ferramentas CLI ───────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    git curl wget tree btop vim nano \
    ca-certificates gnupg lsb-release software-properties-common \
    iputils-ping iproute2 net-tools

# ── fastfetch — .deb direto do GitHub Releases (mais confiável que PPA no chroot)
_FF_VER=$(curl -fsSL --connect-timeout 10 \
    https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
    2>/dev/null | grep -o '"tag_name": "[^"]*"' | grep -o '[0-9][^"]*' || echo "2.65.2")
_FF_URL="https://github.com/fastfetch-cli/fastfetch/releases/download/${_FF_VER}/fastfetch-linux-amd64.deb"
curl -fsSL --connect-timeout 20 "$_FF_URL" -o /tmp/fastfetch.deb 2>/dev/null && \
    dpkg -i /tmp/fastfetch.deb 2>/dev/null && \
    rm -f /tmp/fastfetch.deb || \
    { echo "fastfetch .deb falhou — tentando PPA..."; \
      add-apt-repository -y ppa:zhangsongcui3371/fastfetch 2>/dev/null || true; \
      apt-get update -qq 2>/dev/null || true; \
      apt-get install -y --no-install-recommends fastfetch 2>/dev/null || true; }

# ── Firefox .deb (sem snap) via repo Mozilla ──────────────────────────────────
# Tentativa 1: repo Mozilla (firefox sem snap)
install -d -m 0755 /etc/apt/keyrings
curl -fsSL --connect-timeout 15 https://packages.mozilla.org/apt/repo-signing-key.gpg \
    -o /etc/apt/keyrings/packages.mozilla.org.asc 2>/dev/null || true
if [ -s /etc/apt/keyrings/packages.mozilla.org.asc ]; then
    echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' \
        > /etc/apt/sources.list.d/mozilla.list
    apt-get update -qq 2>/dev/null || true
    apt-get install -y firefox 2>/dev/null && echo "Firefox (Mozilla) instalado." || {
        # Tentativa 2: firefox-esr dos repos padrão (sem snap)
        apt-get install -y firefox-esr 2>/dev/null || true
    }
else
    # Sem acesso ao repo Mozilla — usar firefox-esr dos repos Ubuntu
    apt-get install -y firefox-esr 2>/dev/null || true
fi
# Garantir que snapd não será usado para reinstalar o firefox
cat > /etc/apt/preferences.d/firefox-no-snap << 'SNAP_BLOCK'
Package: firefox
Pin: release o=Ubuntu*
Pin-Priority: -1
SNAP_BLOCK

# ── Papirus ───────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends papirus-icon-theme || true

# ── GNOME Shell (sem gnome-core para evitar nautilus/gnome-terminal/yelp) ───────
# gnome-core puxa nautilus, gnome-terminal, yelp, gnome-control-center — não queremos.
# Instalamos apenas o mínimo necessário para a sessão GNOME funcionar.
apt-get install -y --no-install-recommends \
    gnome-shell \
    gdm3 \
    gnome-session \
    gnome-settings-daemon \
    gnome-text-editor \
    gnome-disk-utility \
    eog \
    file-roller \
    gvfs gvfs-backends \
    dconf-cli dconf-editor \
    adwaita-icon-theme-full \
    fonts-cantarell fonts-dejavu fonts-dejavu-core \
    fonts-noto-core fonts-liberation \
    libglib2.0-bin

# gnome-shell-extensions contém user-theme, places-menu, etc.
# gnome-shell-extension-user-themes é apenas um metapacote alias no Ubuntu — nem sempre existe
apt-get install -y --no-install-recommends gnome-shell-extensions 2>/dev/null || \
apt-get install -y --no-install-recommends gnome-shell-extension-user-themes 2>/dev/null || true

apt-get install -y policykit-1 polkitd || true

apt-get install -y bluez || true
apt-get install -y touchegg || true

apt-get install -y gnome-keyring libpam-gnome-keyring || true

# Remover apps GNOME indesejados que possam ter vindo como dependência
apt-get purge -y \
    nautilus yelp gnome-terminal \
    gnome-control-center gnome-control-center-data \
    gnome-online-accounts totem rhythmbox \
    cheese simple-scan 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true


# ── Gráficos / Wayland ────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    xwayland xserver-xorg-input-all \
    pipewire pipewire-pulse wireplumber mesa-utils

# ── Network ───────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    network-manager network-manager-gnome wpasupplicant \
    isc-dhcp-client

# ── Plymouth ──────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends plymouth plymouth-themes

# ── Casper (live boot) ────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends casper lupin-casper 2>/dev/null || \
apt-get install -y --no-install-recommends casper || true

# ── Filesystem ────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    e2fsprogs ntfs-3g exfatprogs dosfstools udisks2

# ── initramfs-tools ───────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends initramfs-tools

# ── Flatpak ───────────────────────────────────────────────────────────────────
apt-get install -y --no-install-recommends flatpak xdg-desktop-portal-gnome || true

# ── Ferramentas de build ──────────────────────────────────────────────────────
apt-get install -y --no-install-recommends \
    build-essential pkg-config \
    libgtk-4-dev libadwaita-1-dev libvte-2.91-gtk4-dev librsvg2-bin \
    python3 python3-gi python3-gi-cairo \
    gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-vte-3.91 || true

# ── Cursor GoogleDot-Black ────────────────────────────────────────────────────
mkdir -p /tmp/googledot && cd /tmp/googledot
curl -fsSL https://github.com/ful1e5/Google_Cursor/releases/latest/download/GoogleDot-Black.tar.gz \
    -o googledot.tar.gz 2>/dev/null || \
curl -fsSL https://github.com/ful1e5/Google_Cursor/releases/download/v2.0.0/GoogleDot-Black.tar.gz \
    -o googledot.tar.gz 2>/dev/null || true
if [ -f googledot.tar.gz ]; then
    tar -xzf googledot.tar.gz -C /usr/share/icons/ 2>/dev/null || true
    echo 'GoogleDot-Black instalado.'
fi
cd / && rm -rf /tmp/googledot

# ── Limpar ────────────────────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT

    log_ok "Pacotes instalados."
}

# ==============================================================================
# STAGE 5: Drivers de vídeo
# ==============================================================================
stage_install_drivers() {
    log_stage "Stage 5 — Instalando/atualizando drivers de vídeo"

    chroot "$BUILD_ROOT" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq

        # Instalar drivers genéricos que cobrem a maioria do hardware
        apt-get install -y --no-install-recommends \
            xserver-xorg-video-all \
            mesa-vulkan-drivers \
            vainfo \
            intel-media-va-driver-non-free || true

        # Adicionar PPA da nvidia (se disponível)
        # O usuário pode instalar o driver proprietário depois via alipack
        apt-get install -y --no-install-recommends \
            xserver-xorg-video-nouveau || true

        # VirtualBox Guest (VMSVGA) — falha silenciosa se DKMS não compilar
        apt-get install -y --no-install-recommends \
            virtualbox-guest-utils virtualbox-guest-x11 2>/dev/null || true

        apt-get clean
    "

    # Blacklist vmwgfx (driver VMware) — conflita com VirtualBox VMSVGA e
    # causa "unsupported hypervisor" errors que travam o boot gráfico
    mkdir -p "${BUILD_ROOT}/etc/modprobe.d"
    cat > "${BUILD_ROOT}/etc/modprobe.d/alinix-blacklist.conf" << 'EOF'
# vmwgfx: driver VMware — não usar no VirtualBox (causa DRM errors)
blacklist vmwgfx
EOF

    # Criar dummies de firmware para silenciar avisos do i915 no initramfs
    mkdir -p "${BUILD_ROOT}/lib/firmware/i915"
    for fw in dg2_guc_70.bin mtl_gsc_1.bin skl_huc_2.0.0.bin bxt_huc_2.0.0.bin kbl_huc_4.0.0.bin; do
        touch "${BUILD_ROOT}/lib/firmware/i915/${fw}"
    done

    # Criar dummies de firmware Realtek (r8169) para silenciar avisos do initramfs
    mkdir -p "${BUILD_ROOT}/lib/firmware/rtl_nic"
    for fw in \
        rtl8168e-3.fw rtl8168e-2.fw rtl8168e-1.fw \
        rtl8168d-2.fw rtl8168d-1.fw \
        rtl8168h-2.fw rtl8168h-1.fw \
        rtl8168g-3.fw rtl8168g-2.fw rtl8168g-1.fw \
        rtl8106e-2.fw rtl8106e-1.fw \
        rtl8125a-3.fw rtl8125b-2.fw \
        rtl8411-2.fw rtl8411-1.fw \
        rtl8402-1.fw rtl8101e-4.fw; do
        touch "${BUILD_ROOT}/lib/firmware/rtl_nic/${fw}"
    done

    log_ok "Drivers de vídeo instalados."
}

# ==============================================================================
# STAGE 5.5: Instalar kernel no chroot
# Suporta: Kernel-Lix 6.x, Kernel-Lix 7.x, kernel genérico (apt)
# ==============================================================================
stage_install_lix_kernel() {
    log_stage "Stage 5.5 — Instalando kernel no chroot (modo: ${KERNEL_MODE})"

    # ── Kernel genérico via apt ──────────────────────────────────────────────
    if [[ "$KERNEL_MODE" == "generic" ]]; then
        log_info "Instalando linux-image-generic via apt..."
        chroot "$BUILD_ROOT" /bin/bash -c "
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y --no-install-recommends \
                linux-image-generic linux-headers-generic 2>&1
        "
        log_ok "Kernel genérico instalado."
        log_info "initramfs será gerado pelo Casper no Stage 13.5"
        return 0
    fi

    # ── Kernel-Lix (6.x ou 7.x) — procura em dist/ primeiro ────────────────
    local KSRC
    case "$KERNEL_MODE" in
        lix7) KSRC="$LIX7_SRC" ;;
        *)    KSRC="$LIX6_SRC" ;;
    esac

    # Descobrir o vmlinuz publicado em dist/ para esta versão
    local DIST_VMLINUZ DIST_INITRD KVER
    local kver_prefix
    case "$KERNEL_MODE" in
        lix7) kver_prefix="7" ;;
        *)    kver_prefix="6" ;;
    esac

    DIST_VMLINUZ=$(find "$LIX_DIST" -maxdepth 1 -name "vmlinuz-${kver_prefix}*-lix" 2>/dev/null \
                   | sort | tail -1 || true)
    DIST_INITRD=$(find "$LIX_DIST" -maxdepth 1 -name "initrd-${kver_prefix}*-lix.img" 2>/dev/null \
                  | sort | tail -1 || true)

    if [[ -n "$DIST_VMLINUZ" ]]; then
        KVER=$(basename "$DIST_VMLINUZ" | sed 's/^vmlinuz-//')
        log_info "Usando kernel pré-compilado de dist/: $KVER"
        mkdir -p "${BUILD_ROOT}/boot"
        cp -v "$DIST_VMLINUZ" "${BUILD_ROOT}/boot/vmlinuz-${KVER}"
        local DIST_SYSMAP="${LIX_DIST}/System.map-${KVER}"
        local DIST_CONFIG="${LIX_DIST}/config-${KVER}"
        [[ -f "$DIST_SYSMAP" ]] && cp -v "$DIST_SYSMAP" "${BUILD_ROOT}/boot/System.map-${KVER}"
        [[ -f "$DIST_CONFIG"  ]] && cp -v "$DIST_CONFIG"  "${BUILD_ROOT}/boot/config-${KVER}"
    elif [[ -d "$KSRC" ]]; then
        log_warn "dist/ sem vmlinuz para ${kver_prefix}.x — usando árvore do kernel: $KSRC"
        KVER=$(make -s -C "$KSRC" kernelrelease 2>/dev/null \
               || basename "$KSRC" | sed 's/linux-//')
        log_info "Versão do Kernel-Lix detectada: $KVER"
        mkdir -p "${BUILD_ROOT}/boot"
        cp -v "${KSRC}/arch/x86/boot/bzImage" "${BUILD_ROOT}/boot/vmlinuz-${KVER}"
        [[ -f "${KSRC}/System.map" ]] && cp -v "${KSRC}/System.map" "${BUILD_ROOT}/boot/System.map-${KVER}"
        [[ -f "${KSRC}/.config"    ]] && cp -v "${KSRC}/.config"    "${BUILD_ROOT}/boot/config-${KVER}"
    else
        log_error "Nenhum artefato encontrado em dist/ nem em $KSRC"
        log_error "Execute: cd ${LIX_DIR} && ./build.sh build"
        exit 1
    fi

    # Instalar módulos (necessário para depmod e para o initramfs incluí-los)
    if [[ -d "$KSRC" ]]; then
        log_info "Instalando módulos de $KSRC em ${BUILD_ROOT}..."
        make -C "$KSRC" INSTALL_MOD_PATH="${BUILD_ROOT}" modules_install 2>&1 | tail -n 5
    else
        log_warn "Árvore do kernel não disponível — módulos não instalados (usando apenas os do chroot)"
    fi

    # Módulo Rust alinix-lsm (opcional)
    local LSM_KO="${LIX_DIR}/src/alinix-lsm/alinix_lsm.ko"
    if [[ -f "$LSM_KO" ]]; then
        log_info "Instalando alinix_lsm.ko..."
        mkdir -p "${BUILD_ROOT}/lib/modules/${KVER}/kernel/security"
        cp -v "$LSM_KO" "${BUILD_ROOT}/lib/modules/${KVER}/kernel/security/"
        chroot "${BUILD_ROOT}" depmod -a "${KVER}"
    else
        log_warn "Módulo alinix_lsm.ko não encontrado (não-crítico)."
    fi

    log_info "initramfs será gerado pelo Casper no Stage 13.5 (não copiando init Rust para o chroot)"
}

# ==============================================================================
# STAGE 6: Aplicar FHS Alinix
# ==============================================================================
stage_apply_fhs() {
    log_stage "Stage 6 — Aplicando hierarquia FHS Alinix"

    # Executar o script fhs-map.sh que já existe no projeto
    if [[ -f "${SCRIPT_DIR}/sys/fhs/fhs-map.sh" ]]; then
        ALINIX_ROOT="$BUILD_ROOT" bash "${SCRIPT_DIR}/sys/fhs/fhs-map.sh"
        log_ok "FHS Alinix aplicada via fhs-map.sh"
    else
        log_error "fhs-map.sh não encontrado!"
        exit 1
    fi

    # ── /home -> /Users bind mount ───────────────────────────────────────────
    if ! grep -q "/Users" "${BUILD_ROOT}/etc/fstab" 2>/dev/null; then
        echo -e "\n# Alinix FHS\n/home /Users none bind 0 0" >> "${BUILD_ROOT}/etc/fstab"
    fi

    # ── /etc -> /Etc bind mount (ARCHITECTURE.md: /Etc ≡ /etc) ──────────────
    # /Etc é o ponto de montagem visível; /etc continua sendo o real
    mkdir -p "${BUILD_ROOT}/Etc"
    if ! grep -q "/Etc" "${BUILD_ROOT}/etc/fstab" 2>/dev/null; then
        echo "/etc /Etc none bind 0 0" >> "${BUILD_ROOT}/etc/fstab"
    fi

    # ── Configurar HOME para /Users/$USER em todos os contextos ──────────────
    # Mesmo em TTY, $HOME deve ser /Users/$USER
    # O bind mount /home -> /Users garante que /Users/$USER ≡ /home/$USER
cat > "${BUILD_ROOT}/etc/profile.d/alinix-home.sh" << 'PROFILE'
# Alinix: redirecionar HOME para /Users/$USER
if [ "$(id -u)" -ne 0 ] && [ -n "$USER" ]; then
    export HOME="/Users/$USER"
fi
PROFILE

    # Sincronia para zsh login: /etc/zsh/zprofile já inclui /etc/profile
    # no Ubuntu/Debian, mas garantir que o caminho de perfil padrão está ativo
    mkdir -p "${BUILD_ROOT}/etc/zsh"
    if ! grep -q "source /etc/profile" "${BUILD_ROOT}/etc/zsh/zprofile" 2>/dev/null; then
        echo 'source /etc/profile 2>/dev/null || true' >> "${BUILD_ROOT}/etc/zsh/zprofile"
    fi

    # systemd environment.d: não é possível usar variáveis como $USER aqui
    # (environment.d não expande variáveis de shell). A lógica de HOME
    # é tratada pelo profile.d/alinix-home.sh (para shells interativos)
    # e pelo PAM (pam_env) para sessões GDM. Nenhum valor estático serve
    # porque HOME depende do usuário logado — removemos o arquivo para
    # evitar sobrescrever HOME com um valor errado ("/Users" sem o username).
    rm -f "${BUILD_ROOT}/etc/environment.d/alinix-home.conf" 2>/dev/null || true

    # ── NSS: Mudar o home padrão de novos usuários para /Users ───────────────
    # adduser.conf
    if [[ -f "${BUILD_ROOT}/etc/adduser.conf" ]]; then
        sed -i 's|^DHOME=.*|DHOME=/Users|' "${BUILD_ROOT}/etc/adduser.conf"
    fi
    # Garantir DHOME= mesmo que a chave não existisse
    grep -q '^DHOME=' "${BUILD_ROOT}/etc/adduser.conf" 2>/dev/null || \
        echo 'DHOME=/Users' >> "${BUILD_ROOT}/etc/adduser.conf"

    # ── login.defs: HOME_MODE (permissões do diretório home) ──────────────────
    # Nota: NÃO existe opção "HOME" no login.defs. Usamos /etc/default/useradd
    # e /etc/adduser.conf para definir o diretório base dos usuários (/Users).

    # ── useradd default ──────────────────────────────────────────────────────
    mkdir -p "${BUILD_ROOT}/etc/default"
    cat > "${BUILD_ROOT}/etc/default/useradd" << 'EOF'
SHELL=/bin/zsh
HOME=/Users
SKEL=/etc/skel
CREATE_MAIL_SPOOL=no
EOF

    # ── Configurar udisks2 para montar em /Volumes ───────────────────────────
    mkdir -p "${BUILD_ROOT}/etc/udisks2"
    cat > "${BUILD_ROOT}/etc/udisks2/udisks2.conf" << 'EOF'
[udisks2]

[defaults]
encryption=luks2

[/org/freedesktop/UDisks2/block-devices]
# Montar volumes removíveis em /Volumes/<label>
# ao invés de /run/media/$USER
EOF

    # Regra udev para montagem em /Volumes
    mkdir -p "${BUILD_ROOT}/etc/udev/rules.d"
    cat > "${BUILD_ROOT}/etc/udev/rules.d/99-alinix-volumes.rules" << 'EOF'
# Alinix: Redirecionar montagens de mídia removível para /Volumes
ENV{UDISKS_FILESYSTEM_SHARED}="1"
EOF

    # Configuração do udisks2 mount_options para /Volumes
    mkdir -p "${BUILD_ROOT}/etc/udisks2/mount_options.conf.d"
    cat > "${BUILD_ROOT}/etc/udisks2/mount_options.conf.d/alinix.conf" << 'EOF'
[defaults]
defaults=nosuid,nodev
allow=exec,noexec,nodev,nosuid,atime,noatime,nodiratime,ro,rw,sync,dirsync,noload

btrfs_defaults=nosuid,nodev
btrfs_allow=compress,compress-force,datacow,nodatacow,datasum,nodatasum,degraded,device,discard,noacl,noatime,nodiratime,relatime,space_cache,ssd,nossd

ntfs_defaults=nosuid,nodev,uid=$UID,gid=$GID
ntfs_allow=

vfat_defaults=nosuid,nodev,uid=$UID,gid=$GID,shortname=mixed,utf8=1
vfat_allow=flush
EOF

    log_ok "FHS e mount binds configurados."
}

# ==============================================================================
# STAGE 7: ZSH como shell padrão + oh-my-zsh + skel
# ==============================================================================
stage_setup_zsh() {
    log_stage "Stage 7 — Configurando ZSH como shell padrão"

    local SKEL_SRC="${SCRIPT_DIR}/sys/skel"
    local SKEL_DST="${BUILD_ROOT}/etc/skel"

    # ── Copiar arquivos do skel que criamos ───────────────────────────────────
    if [[ -d "$SKEL_SRC" ]]; then
        # Copia apenas arquivos/diretórios — ignora . e .. que o glob .* inclui
        for f in "${SKEL_SRC}/"* "${SKEL_SRC}/".*; do
            local base
            base="$(basename "$f")"
            [[ "$base" == "." || "$base" == ".." ]] && continue
            cp -a "$f" "${SKEL_DST}/" 2>/dev/null || true
        done
        log_ok "Skel copiado de sys/skel/"
    else
        log_warn "sys/skel/ não encontrado. Criando configuração ZSH básica."
    fi

    # ── Instalar oh-my-zsh no skel (clonado no host, depois copiado) ──────────
    local OMZ_DST="${SKEL_DST}/.oh-my-zsh"

    if [[ ! -d "$OMZ_DST" ]]; then
        log_info "Clonando oh-my-zsh no host..."
        git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DST"
    fi

    # Plugins extras
    if [[ ! -d "${OMZ_DST}/custom/plugins/zsh-autosuggestions" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "${OMZ_DST}/custom/plugins/zsh-autosuggestions" 2>/dev/null || true
    fi
    if [[ ! -d "${OMZ_DST}/custom/plugins/zsh-syntax-highlighting" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "${OMZ_DST}/custom/plugins/zsh-syntax-highlighting" 2>/dev/null || true
    fi

    # Copiar tema Alinix para o oh-my-zsh
    mkdir -p "${OMZ_DST}/custom/themes"
    if [[ -f "${SKEL_SRC}/alinix.zsh-theme" ]]; then
        cp "${SKEL_SRC}/alinix.zsh-theme" "${OMZ_DST}/custom/themes/alinix.zsh-theme"
    fi

    # ── ZSH como shell padrão para TODOS os usuários e root ──────────────────
    chroot "$BUILD_ROOT" /bin/bash -c "
        # Mudar shell padrão do root
        chsh -s /bin/zsh root

        # Garantir que o shell padrão de novos usuários será zsh
        sed -i 's|^DSHELL=.*|DSHELL=/bin/zsh|' /etc/adduser.conf 2>/dev/null || true
    "

    # ── .zshrc pro root também ───────────────────────────────────────────────
    if [[ -f "${SKEL_DST}/.zshrc" ]]; then
        cp "${SKEL_DST}/.zshrc" "${BUILD_ROOT}/root/.zshrc"
    fi
    if [[ -d "${SKEL_DST}/.oh-my-zsh" ]]; then
        cp -a "${SKEL_DST}/.oh-my-zsh" "${BUILD_ROOT}/root/.oh-my-zsh" 2>/dev/null || true
    fi

    log_ok "ZSH configurado como shell padrão para todos os usuários."
}

# ==============================================================================
# STAGE 8: Plymouth boot theme
# ==============================================================================
stage_install_plymouth() {
    log_stage "Stage 8 — Instalando tema Plymouth Alinix"

    local PLYMOUTH_SRC="${SCRIPT_DIR}/sys/plymouth/alinix-theme"
    local PLYMOUTH_DST="${BUILD_ROOT}/usr/share/plymouth/themes/alinix-theme"

    if [[ ! -d "$PLYMOUTH_SRC" ]]; then
        log_warn "Tema Plymouth não encontrado em sys/plymouth/alinix-theme/"
        return 0
    fi

    # Converter logo.svg → logo.png no host (onde rsvg-convert está disponível)
    # O SVG usa fill="currentColor" — forçar branco para contrastar com fundo preto
    if [[ -f "${SCRIPT_DIR}/sys/assets/logo.svg" ]]; then
        rsvg-convert -w 256 -h 256 \
            --stylesheet <(echo 'svg { color: white; }') \
            "${SCRIPT_DIR}/sys/assets/logo.svg" \
            -o "${PLYMOUTH_SRC}/logo.png" 2>/dev/null || \
        rsvg-convert -w 256 -h 256 \
            "${SCRIPT_DIR}/sys/assets/logo.svg" \
            -o "${PLYMOUTH_SRC}/logo.png" 2>/dev/null || \
        log_warn "Falha ao converter logo.svg → logo.png"
    fi

    # Copiar tema para o chroot
    mkdir -p "$PLYMOUTH_DST"
    cp -a "${PLYMOUTH_SRC}/"* "$PLYMOUTH_DST/"
    log_ok "Tema Plymouth copiado para o chroot."

    # Definir como tema padrão — escreve direto nos arquivos de config (mais confiável)
    # /etc/plymouth/plymouthd.conf
    mkdir -p "${BUILD_ROOT}/etc/plymouth"
    cat > "${BUILD_ROOT}/etc/plymouth/plymouthd.conf" << 'PLYM'
[Daemon]
Theme=alinix-theme
ShowDelay=0
DeviceTimeout=8
PLYM

    # /usr/share/plymouth/themes/default.plymouth → symlink para o tema
    ln -sfn /usr/share/plymouth/themes/alinix-theme/alinix-theme.plymouth \
        "${BUILD_ROOT}/usr/share/plymouth/themes/default.plymouth" 2>/dev/null || true

    # Também rodar plymouth-set-default-theme e update-alternatives se disponível no chroot
    chroot "$BUILD_ROOT" /bin/bash -c "
        if command -v update-alternatives &>/dev/null; then
            update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/alinix-theme/alinix-theme.plymouth 150 2>/dev/null || true
            update-alternatives --set default.plymouth /usr/share/plymouth/themes/alinix-theme/alinix-theme.plymouth 2>/dev/null || true
        fi
        plymouth-set-default-theme alinix-theme 2>/dev/null || true
    "
    log_ok "Tema alinix-theme definido como padrão."

    # Parâmetros de kernel no GRUB para activar Plymouth e configurar o tema
    # plymouth.use-simpledrm: modo gráfico compatível com VMs (VirtualBox, QEMU)
    # sem ele, ESC/Tab não funcionam e a tela pode ficar presa
    mkdir -p "${BUILD_ROOT}/etc/default"
    mkdir -p "${BUILD_ROOT}/boot/grub/themes/alinix"
    cp -r "${SCRIPT_DIR}/sys/assets/grub-theme/alinix/"* "${BUILD_ROOT}/boot/grub/themes/alinix/"

    cat > "${BUILD_ROOT}/etc/default/grub" << 'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Alinix"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash plymouth.use-simpledrm plymouth.ignore-serial-consoles"
GRUB_CMDLINE_LINUX=""
GRUB_THEME="/boot/grub/themes/alinix/theme.txt"
GRUB_GFXMODE="auto"
GRUB_GFXPAYLOAD_LINUX="keep"
EOF

    log_ok "Plymouth tema Alinix e tema GRUB configurados."
}

# ==============================================================================
# STAGE 9: Permissões e grupo appmgr
# ==============================================================================
stage_setup_permissions() {
    log_stage "Stage 9 — Configurando permissões e grupo appmgr"

    chroot "$BUILD_ROOT" /bin/bash -c "
        # Criar grupo/usuário polkitd (evita erro de tmpfiles.d no boot)
        # O systemd-sysusers não roda no chroot, então criamos manualmente
        getent group polkitd  >/dev/null 2>&1 || groupadd --system polkitd
        getent passwd polkitd >/dev/null 2>&1 || \
            useradd --system --no-create-home --shell /usr/sbin/nologin \
                    --gid polkitd --comment 'PolicyKit daemon' polkitd

        # Criar grupo appmgr
        groupadd -f appmgr

        # Configurar sudoers — usuário live tem NOPASSWD total (modo live)
        # appmgr tem acesso escopado ao alipack
        cat > /etc/sudoers.d/alinix-live << 'SUDOERS'
# Alinix: usuário live pode usar sudo sem senha
alinix-live ALL=(ALL) NOPASSWD: ALL
SUDOERS
        chmod 0440 /etc/sudoers.d/alinix-live

        cat > /etc/sudoers.d/appmgr << 'SUDOERS'
# Alinix: grupo appmgr pode executar apenas o alipack como root
%appmgr ALL=(root) NOPASSWD: /usr/bin/alipack
SUDOERS
        chmod 0440 /etc/sudoers.d/appmgr

        # Polkit policy para alipack
        mkdir -p /usr/share/polkit-1/actions
        cat > /usr/share/polkit-1/actions/org.alinix.alipack.policy << 'POLKIT'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE policyconfig PUBLIC
 \"-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN\"
 \"http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd\">
<policyconfig>
  <vendor>Alinix</vendor>
  <vendor_url>https://alinix.dev</vendor_url>

  <action id=\"org.alinix.alipack.install\">
    <description>Instalar pacotes via alipack</description>
    <message>Autenticação necessária para instalar pacotes.</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key=\"org.freedesktop.policykit.exec.path\">/usr/bin/alipack</annotate>
  </action>
</policyconfig>
POLKIT

        # Travar conta root por padrão (Modo Desenvolvedor desativado)
        passwd -l root 2>/dev/null || true
    "

    # Configurar lock-apt (bloquear apt direto para usuários normais)
    if [[ -f "${SCRIPT_DIR}/sys/userland/lock-apt.sh" ]]; then
        ALINIX_ROOT="$BUILD_ROOT" bash "${SCRIPT_DIR}/sys/userland/lock-apt.sh" || \
            log_warn "lock-apt.sh falhou (não-crítico)"
    fi

    log_ok "Permissões e grupo appmgr configurados."
}

# ==============================================================================
# STAGE 9.5: Clonar / atualizar repositórios dos apps Alinix
# ==============================================================================
# Mapeamento: <nome-da-pasta-em-apps/> => <url-do-repositorio-git>
# Quando o link do repo não estiver definido ainda, deixa vazio e o stage
# simplesmente pula esse app (sem erro).
declare -A ALINIX_APP_REPOS=(
    ["erasshell"]="https://github.com/jefferson-it/erasshell.git"
    ["alinix-dock"]="https://github.com/jefferson-it/alinix-dock.git"
    ["alinix-init"]="https://github.com/jefferson-it/alinstaler.git"
    ["alinix-settings"]=""   # fork GCC — repo a definir
    ["ali"]="https://github.com/jefferson-it/ali.git"
    ["alipack"]="https://github.com/jefferson-it/alipack.git"
    ["alistaller"]=""        # repo a definir
    ["menu-global"]="https://github.com/jefferson-it/menu-global.git"
    ["menu-global-gtk4"]="https://github.com/jefferson-it/menu-global-gtk4.git"
    ["themes"]="https://github.com/jefferson-it/alinix-themes.git"
    ["wobbly-windows"]="https://github.com/jefferson-it/wobbly-windows.git"
    ["quicklook"]="https://github.com/jefferson-it/quicklook.git"
    ["pkg-compat"]="https://github.com/jefferson-it/alipack-pkg-compact.git"
    ["desktop/jterminal"]="https://github.com/jefferson-it/JTerminal.git"
    ["desktop/jexplorer"]="https://github.com/jefferson-it/JExplorer.git"
    ["desktop/config-app"]="https://github.com/jefferson-it/alinix-settings.git"
)

stage_clone_apps() {
    log_stage "Stage 9.5 — Sincronizando repositórios dos apps"

    local APPS_BASE="${SCRIPT_DIR}/apps"

    for app_path in "${!ALINIX_APP_REPOS[@]}"; do
        local repo_url="${ALINIX_APP_REPOS[$app_path]}"
        local app_dir="${APPS_BASE}/${app_path}"

        if [[ -z "$repo_url" ]]; then
            log_warn "[${app_path}] URL do repositório não configurada — pulando"
            continue
        fi

        if [[ -d "${app_dir}/.git" ]]; then
            log_info "[${app_path}] já existe — fazendo git pull..."
            if git -C "$app_dir" remote get-url origin 2>/dev/null | grep -qF "$repo_url"; then
                git -C "$app_dir" pull --ff-only 2>&1 | tail -2 && \
                    log_ok "[${app_path}] atualizado" || \
                    log_warn "[${app_path}] git pull falhou (pode ser branch divergente)"
            else
                log_warn "[${app_path}] origin diverge do mapa — pulando pull para não sobrescrever"
            fi
        else
            log_info "[${app_path}] clonando de ${repo_url}..."
            mkdir -p "$app_dir"
            git clone --depth=1 "$repo_url" "$app_dir" 2>&1 | tail -2 && \
                log_ok "[${app_path}] clonado" || \
                log_warn "[${app_path}] git clone falhou"
        fi
    done

    log_ok "Sincronização de apps concluída."
}

# ==============================================================================
# STAGE 10: Compilar e instalar apps do Alinix no chroot
# ==============================================================================
stage_install_apps() {
    log_stage "Stage 10 — Compilando apps no host e instalando no chroot"

    local APPS="${SCRIPT_DIR}/apps"
    local DST="${BUILD_ROOT}/usr"
    local REAL_USER="${SUDO_USER:-root}"
    local REAL_HOME
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

    # Função interna: compila como usuário real, instala como root
    _compile_rust() {
        local label="$1" dir="$2" binary="$3" dest_name="${4:-$3}"
        log_info "[$label] compilando..."
        # Garantir que target/ seja do usuário real (evita "Permission denied" se root compilou antes)
        if [[ -n "${SUDO_USER:-}" ]]; then
            [[ -d "${dir}/target" ]] && chown -R "$REAL_USER" "${dir}/target" 2>/dev/null || true
            sudo -u "$REAL_USER" env \
                PATH="$PATH" HOME="$REAL_HOME" \
                cargo build --release --manifest-path "${dir}/Cargo.toml" 2>&1 \
                | tail -3 || { log_warn "[$label] compilação falhou"; return 1; }
        else
            cargo build --release --manifest-path "${dir}/Cargo.toml" 2>&1 \
                | tail -3 || { log_warn "[$label] compilação falhou"; return 1; }
        fi
        install -Dm755 "${dir}/target/release/${binary}" "${DST}/bin/${dest_name}"
        log_ok "[$label] instalado em ${DST}/bin/${dest_name}"
    }

    _install_file() {
        local src="$1" dst="$2" mode="${3:-644}"
        mkdir -p "$(dirname "$dst")"
        install -Dm"$mode" "$src" "$dst"
    }

    _install_dir() {
        local src="$1" dst="$2"
        mkdir -p "$dst"
        cp -r "${src}/." "$dst/"
        find "$dst" -type d -exec chmod 755 {} +
        find "$dst" -type f -exec chmod 644 {} +
    }

    # ── Rust: alipack ──────────────────────────────────────────────────────
    _compile_rust "alipack" "${APPS}/alipack" "alipack" || true

    # ── Rust: pkg-compat ──────────────────────────────────────────────────
    _compile_rust "pkg-compat" "${APPS}/pkg-compat" "alinix-pkg-compat" || true

    # ── Rust: alinix-init ─────────────────────────────────────────────────
    _compile_rust "alinix-init" "${APPS}/alinix-init" "init" "alinix-init" || true
    if [[ -f "${APPS}/alinix-init/build-initramfs.sh" ]]; then
        install -Dm755 "${APPS}/alinix-init/build-initramfs.sh" "${DST}/bin/alinix-build-initramfs"
    fi

    # ── Python: Alí ───────────────────────────────────────────────────────
    log_info "[ali] instalando..."
    mkdir -p "${DST}/bin" "${DST}/share/applications" "${DST}/share/glib-2.0/schemas"
    install -Dm755 "${APPS}/ali/ali.py" "${DST}/bin/ali"
    [[ -f "${APPS}/ali/ali.desktop" ]] && \
        _install_file "${APPS}/ali/ali.desktop" "${DST}/share/applications/com.alinix.ali.desktop"
    [[ -f "${APPS}/ali/com.alinix.ali.gschema.xml" ]] && \
        _install_file "${APPS}/ali/com.alinix.ali.gschema.xml" "${DST}/share/glib-2.0/schemas/com.alinix.ali.gschema.xml"
    log_ok "[ali] instalado"

    # ── Python: JExplorer ─────────────────────────────────────────────────
    log_info "[jexplorer] instalando..."
    install -Dm755 "${APPS}/desktop/jexplorer/jexplorer.py" "${DST}/bin/jexplorer"
    cat > "${DST}/share/applications/com.alinix.jexplorer.desktop" << 'DESKTOP'
[Desktop Entry]
Name=JExplorer
GenericName=Gerenciador de Arquivos
Exec=jexplorer %u
Icon=system-file-manager
Terminal=false
Type=Application
Categories=GNOME;GTK;FileManager;
MimeType=inode/directory;
DESKTOP
    log_ok "[jexplorer] instalado"

    # ── Python: JTerminal ─────────────────────────────────────────────────
    log_info "[jterminal] instalando..."
    install -Dm755 "${APPS}/desktop/jterminal/jterminal.py" "${DST}/bin/jterminal"
    cat > "${DST}/share/applications/com.alinix.jterminal.desktop" << 'DESKTOP'
[Desktop Entry]
Name=JTerminal
GenericName=Terminal
Exec=jterminal
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=GNOME;GTK;System;TerminalEmulator;
DESKTOP
    log_ok "[jterminal] instalado"

    # ── alinix-settings ícone adaptativo ─────────────────────────────────
    log_info "[alinix-settings] instalando ícone..."
    mkdir -p "${DST}/share/icons/hicolor/scalable/apps"
    cp "${SCRIPT_DIR}/sys/assets/logo.svg" \
        "${DST}/share/icons/hicolor/scalable/apps/alinix-settings.svg" 2>/dev/null || true
    cp "${SCRIPT_DIR}/sys/assets/logo.svg" \
        "${DST}/share/icons/hicolor/scalable/apps/alinix-logo.svg" 2>/dev/null || true
    mkdir -p "${DST}/share/pixmaps"
    cp "${SCRIPT_DIR}/sys/assets/logo.svg" \
        "${DST}/share/pixmaps/alinix-settings.svg" 2>/dev/null || true
    # .desktop do alinix-settings
    install -Dm755 "${APPS}/desktop/config-app/alinix-settings.py" "${DST}/bin/alinix-settings"
    _install_file "${APPS}/desktop/config-app/alinix-settings.desktop" \
        "${DST}/share/applications/alinix-settings.desktop"
    log_ok "[alinix-settings] instalado"

    # ── command-key ───────────────────────────────────────────────────────
    if [[ -f "${APPS}/desktop/command-key/apply-command-key.sh" ]]; then
        log_info "[command-key] instalando..."
        install -Dm755 "${APPS}/desktop/command-key/apply-command-key.sh" \
            "${DST}/bin/alinix-apply-command-key"
        if [[ -f "${APPS}/desktop/command-key/keynames.conf" ]]; then
            _install_file "${APPS}/desktop/command-key/keynames.conf" \
                "${DST}/share/alinix/keynames.conf"
        fi
        log_ok "[command-key] instalado"
    fi

    # ── ErasShell (extensão GNOME Shell) ──────────────────────────────────
    log_info "[erasshell] instalando..."
    if ! bash "${APPS}/erasshell/install-erasshell.sh" --root "$BUILD_ROOT"; then
        log_warn "[erasshell] falhou (não-crítico)"
    else
        log_ok "[erasshell] instalado"
    fi

    # ── Alinix Dock (extensão GNOME Shell) ────────────────────────────────
    log_info "[alinix-dock] instalando..."
    if [[ -d "${APPS}/alinix-dock/alinix-dock@alinix.osx" ]]; then
        bash "${APPS}/alinix-dock/install.sh" --root "$BUILD_ROOT" 2>&1 | tail -3 || \
            log_warn "[alinix-dock] falhou (não-crítico)"
        log_ok "[alinix-dock] instalado"
    else
        log_warn "[alinix-dock] fonte não encontrada"
    fi

    # ── Desktop UX (tema, menu-global, wobbly, touchegg, gsettings) ───────
    log_info "[desktop-ux] instalando..."
    if ! ALINIX_ROOT="$BUILD_ROOT" bash "${APPS}/desktop/install-desktop-ux.sh"; then
        log_warn "[desktop-ux] falhou (não-crítico)"
    else
        log_ok "[desktop-ux] instalado"
    fi

    # ── Alinix Settings (fork do gnome-control-center) ───────────────────
    log_info "[alinix-settings] compilando e instalando..."
    if [[ -d "${APPS}/alinix-settings" && -f "${APPS}/alinix-settings/meson.build" ]]; then
        # Instalar deps de build dentro do chroot
        chroot "$BUILD_ROOT" /bin/bash -c "
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                meson ninja-build pkg-config gcc \
                libgtk-4-dev libadwaita-1-dev \
                libglib2.0-dev libglib2.0-bin \
                libjson-glib-dev \
                libsecret-1-dev \
                libpolkit-gobject-1-dev \
                libgnome-bluetooth-3.0-dev \
                libpulse-dev \
                libcolord-dev \
                libcanberra-gtk3-dev \
                libgnome-desktop-4-dev \
                libmm-glib-dev \
                libaccountsservice-dev \
                libkrb5-dev \
                libibus-1.0-dev \
                libcheese-gtk-dev \
                libwacom-dev \
                libxi-dev \
                libx11-dev \
                gettext \
                2>&1 | tail -5
        " || log_warn "[alinix-settings] falha ao instalar deps de build"

        # Copiar fonte para dentro do chroot
        cp -r "${APPS}/alinix-settings" "${BUILD_ROOT}/tmp/alinix-settings-src"

        # Compilar dentro do chroot
        chroot "$BUILD_ROOT" /bin/bash -c "
            cd /tmp/alinix-settings-src
            meson setup _build \
                --prefix=/usr \
                --buildtype=release \
                -Dprofile='' \
                2>&1 | tail -10
            ninja -C _build -j\$(nproc) 2>&1 | tail -10
            ninja -C _build install 2>&1 | tail -5

            # Criar symlink alinix-settings → binário instalado
            ln -sfn /usr/bin/alinix-settings /usr/local/bin/alinix-settings 2>/dev/null || true

            # Limpar build
            rm -rf /tmp/alinix-settings-src
        " && log_ok "[alinix-settings] compilado e instalado" \
          || log_warn "[alinix-settings] falha na compilação (não-crítico)"

        # Remover deps de build para manter ISO enxuto
        chroot "$BUILD_ROOT" /bin/bash -c "
            apt-get remove -y meson ninja-build pkg-config \
                libgtk-4-dev libadwaita-1-dev libglib2.0-dev \
                libjson-glib-dev libsecret-1-dev libpolkit-gobject-1-dev \
                libgnome-bluetooth-3.0-dev libpulse-dev libcolord-dev \
                libcanberra-gtk3-dev libgnome-desktop-4-dev libmm-glib-dev \
                libaccountsservice-dev libkrb5-dev libibus-1.0-dev \
                libcheese-gtk-dev libwacom-dev libxi-dev libx11-dev \
                2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
        "
    else
        log_warn "[alinix-settings] fonte não encontrada em apps/alinix-settings/"
    fi

    # ── Quicklook ─────────────────────────────────────────────────────────
    if [[ -f "${APPS}/quicklook/install.sh" ]]; then
        PREFIX="${DST}" bash "${APPS}/quicklook/install.sh" 2>&1 | tail -3 || \
            log_warn "[quicklook] falhou (não-crítico)"
    fi

    # ── Compilar todos os schemas do chroot ───────────────────────────────
    # ── Alistaller (instalador gráfico do modo live) ──────────────────────────
    log_info "[alistaller] instalando..."
    if [[ -f "${APPS}/alistaller/install.sh" ]]; then
        if ! ALINIX_ROOT="$BUILD_ROOT" bash "${APPS}/alistaller/install.sh"; then
            log_warn "[alistaller] falhou (não-crítico)"
        else
            log_ok "[alistaller] instalado"
        fi
    else
        log_warn "[alistaller] install.sh não encontrado"
    fi

    chroot "$BUILD_ROOT" glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true

    log_ok "Stage 10 concluído."
}

# ==============================================================================
# STAGE 11: Configurar Casper (live boot) + usuário live
# ==============================================================================
stage_setup_live() {
    log_stage "Stage 11 — Configurando modo live (Casper)"

    # ── Copiar wallpaper para o chroot ────────────────────────────────────────
    local WP_SRC="${SCRIPT_DIR}/sys/assets/black-and-white-3840x2160-21293.jpg"
    mkdir -p "${BUILD_ROOT}/usr/share/backgrounds/alinix"
    if [[ -f "$WP_SRC" ]]; then
        cp "$WP_SRC" "${BUILD_ROOT}/usr/share/backgrounds/alinix/alinix-wallpaper-01.jpg"
    fi
    # Symlink do logo para os ícones
    mkdir -p "${BUILD_ROOT}/usr/share/pixmaps"
    cp "${SCRIPT_DIR}/sys/assets/logo.svg" \
       "${BUILD_ROOT}/usr/share/pixmaps/alinix-logo.svg" 2>/dev/null || true

    chroot "$BUILD_ROOT" /bin/bash <<'CHROOT_LIVE'
# ── Usuário live sem senha ────────────────────────────────────────────────────
# Cria o home físico em /home/alinix-live (para o bind mount /home->/Users)
# Depois atualiza passwd para /Users/alinix-live — no boot o bind mount
# faz /Users/alinix-live resolver para /home/alinix-live (que existe).
useradd -m -d /home/alinix-live -s /bin/zsh -G sudo,appmgr -c 'Alinix Live' alinix-live 2>/dev/null || true
usermod -d /Users/alinix-live alinix-live 2>/dev/null || true
echo 'alinix-live:' | chpasswd
# Não forçar expiração de senha
chage -M 99999 alinix-live 2>/dev/null || true

# ── PAM: nullok (senha vazia para autologin) + gnome-keyring ─────────────────
# nullok — permite autenticar com senha vazia (necessário para autologin)
for _pam in common-auth gdm-autologin; do
    if [ -f "/etc/pam.d/${_pam}" ]; then
        sed -i 's/\(pam_unix\.so\)/\1 nullok/' "/etc/pam.d/${_pam}" 2>/dev/null || true
        grep -q "nullok" "/etc/pam.d/${_pam}" 2>/dev/null || \
            sed -i '/^auth.*pam_unix\.so/ s/$/ nullok/' "/etc/pam.d/${_pam}" 2>/dev/null || true
    fi
done

# gnome-keyring — PAM integration apenas para gdm-password e login (TTY).
# gdm-autologin é intencionalmente excluído aqui: com senha vazia, o keyring
# entra em loop tentando destrancar o cofre e congela o boot gráfico.
for _pam in gdm-password login; do
    _file="/etc/pam.d/${_pam}"
    [ ! -f "$_file" ] && continue
    # Adicionar pam_gnome_keyring.so no auth (se ainda não existe)
    if ! grep -q "pam_gnome_keyring.so" "$_file"; then
        if grep -q "^auth.*include.*common-auth" "$_file"; then
            sed -i '/^auth.*include.*common-auth/i auth optional pam_gnome_keyring.so' "$_file"
        else
            echo 'auth optional pam_gnome_keyring.so' >> "$_file"
        fi
    fi
    # Adicionar pam_gnome_keyring.so no session (verificação separada por tipo)
    if ! grep -q "^session.*pam_gnome_keyring" "$_file"; then
        if grep -q "^session.*include.*common-session" "$_file"; then
            sed -i '/^session.*include.*common-session/i session optional pam_gnome_keyring.so auto_start' "$_file"
        elif grep -q "^session.*required.*pam_unix" "$_file"; then
            sed -i '/^session.*required.*pam_unix/a session optional pam_gnome_keyring.so auto_start' "$_file"
        else
            echo 'session optional pam_gnome_keyring.so auto_start' >> "$_file"
        fi
    fi
done

# gdm-autologin: garantir que pam_gnome_keyring.so está comentado/ausente.
# Não adicionamos e comentamos qualquer linha existente para garantir que
# o autologin não trave com senha vazia.
if [ -f "/etc/pam.d/gdm-autologin" ]; then
    sed -i '/pam_gnome_keyring\.so/s/^/#/' /etc/pam.d/gdm-autologin 2>/dev/null || true
fi
# Autologin em todos os TTYs (1-6) — --skip-login elimina a pausa do PAM
for tty_n in 1 2 3 4 5 6; do
    mkdir -p "/etc/systemd/system/getty@tty${tty_n}.service.d"
    cat > "/etc/systemd/system/getty@tty${tty_n}.service.d/autologin.conf" << 'TTYEOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin alinix-live --skip-login --noclear %I $TERM
TTYEOF
done

# ── Autologin GDM ─────────────────────────────────────────────────────────────
mkdir -p /etc/gdm3
    cat > /etc/gdm3/custom.conf << 'EOF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=alinix-live
TimedLoginEnable=false
WaylandEnable=false

[security]
AllowRoot=false

[xdmcp]

[chooser]

[debug]
EOF

# ── TTY autologin no tty1 ─────────────────────────────────────────────────────
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin alinix-live --skip-login --noclear %I $TERM
EOF

# ── Rede: NetworkManager gerencia todas as interfaces no live ─────────────────
systemctl enable NetworkManager 2>/dev/null || true
systemctl enable NetworkManager-dispatcher 2>/dev/null || true

# Limpar regras residuais de unmanaged do Ubuntu Noble
rm -f /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf 2>/dev/null || true
rm -f /etc/NetworkManager/conf.d/10-globally-managed-devices.conf 2>/dev/null || true
sed -i '/unmanaged-devices/d' /etc/NetworkManager/NetworkManager.conf 2>/dev/null || true

# Configuração global forçando o gerenciamento total e o dhclient
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-alinix-live.conf << 'EOF'
[main]
# Como vimos no teste prático, o dhclient funciona perfeitamente
dhcp=dhclient

[keyfile]
# Força o NM a gerenciar todas as placas que encontrar (nada de unmanaged)
unmanaged-devices=none

[device]
wifi.backend=wpa_supplicant
match-device=type:ethernet
managed=1
EOF

# Perfil DHCP padrão (Agora com UUID válido e Match rule)
mkdir -p /etc/NetworkManager/system-connections
cat > /etc/NetworkManager/system-connections/alinix-live-eth.nmconnection << 'EOF'
[connection]
id=Alinix Live Ethernet
uuid=c3b313a2-2591-496f-b670-3d7199c355fc
type=ethernet
autoconnect=true
autoconnect-priority=100

[match]
# Cobre qualquer interface ethernet encontrada (eth0, enp0s3, etc)
original-name=*

[ethernet]

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=stable-privacy
EOF
chmod 600 /etc/NetworkManager/system-connections/alinix-live-eth.nmconnection

# ── dconf: perfil e banco do usuário live ─────────────────────────────────────
mkdir -p /etc/dconf/profile /etc/dconf/db/alinix-live.d

cat > /etc/dconf/profile/alinix-live << 'EOF'
user-db:user
system-db:alinix-live
EOF

cat > /etc/dconf/db/alinix-live.d/00-desktop << 'EOF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/alinix/alinix-wallpaper-01.jpg'
picture-uri-dark='file:///usr/share/backgrounds/alinix/alinix-wallpaper-01.jpg'
picture-options='zoom'
color-shading-type='solid'
primary-color='#0d001a'

[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='alinix-dracula'
icon-theme='Papirus-Dark'
cursor-theme='GoogleDot-Black'
font-name='Cantarell 11'

[org/gnome/shell]
# Impede o GNOME de abrir o Overview automaticamente na primeira sessão
welcome-dialog-last-shown-version='9999.0'

[org/gnome/gnome-session]
# Não exibir o assistente de boas-vindas (first-run wizard)
auto-save-session=false

[org/gnome/desktop/wm/preferences]
button-layout='close,minimize,maximize:appmenu'
theme='alinix-dracula'

[org/gnome/shell]
favorite-apps=['firefox.desktop', 'jexplorer.desktop', 'jterminal.desktop', 'com.alinix.ali.desktop', 'alinix-settings.desktop', 'alinix-installer.desktop', 'org.gnome.TextEditor.desktop']
enabled-extensions=['user-theme@gnome-shell-extensions.gcampax.github.com', 'erasshell@alinix', 'alinix-dock@alinix.osx', 'menu-global-gtk4@alinix.osx', 'wobbly-windows@weinberg.org']

[org/gnome/shell/extensions/user-theme]
name='alinix-dracula'

[org/gnome/desktop/peripherals/touchpad]
natural-scroll=true
tap-to-click=true
two-finger-scrolling-enabled=true

[org/gnome/mutter]
dynamic-workspaces=true
EOF

dconf update 2>/dev/null || true
CHROOT_LIVE

    # ── Tema GTK4 + Flatpak para o usuário live ───────────────────────────────
    # GTK4 ignora /usr/share/themes — lê apenas ~/.config/gtk-4.0/gtk.css
    # Flatpak lê ~/.themes/<nome>/gtk-4.0/ via --filesystem=~/.themes
    local THEME_SRC="${SCRIPT_DIR}/apps/themes/alinix-dracula"
    local LIVE_HOME="${BUILD_ROOT}/home/alinix-live"

    if [[ -d "$THEME_SRC" ]]; then
        # ~/.config/gtk-4.0/ — para apps GTK4 nativos
        mkdir -p "${LIVE_HOME}/.config/gtk-4.0"
        cp "${THEME_SRC}/gtk-4.0/gtk.css"      "${LIVE_HOME}/.config/gtk-4.0/gtk.css"
        cp "${THEME_SRC}/gtk-4.0/gtk-dark.css" "${LIVE_HOME}/.config/gtk-4.0/gtk-dark.css" 2>/dev/null || true
        # Copiar assets se existirem
        [[ -d "${THEME_SRC}/gtk-4.0/assets" ]] && \
            cp -r "${THEME_SRC}/gtk-4.0/assets" "${LIVE_HOME}/.config/gtk-4.0/assets" || true

        # ~/.themes/alinix-dracula/ — para Flatpak (precisa do tema completo)
        mkdir -p "${LIVE_HOME}/.themes"
        cp -r "${THEME_SRC}" "${LIVE_HOME}/.themes/alinix-dracula"

        # ~/.local/share/themes/ — alternativa usada por alguns apps
        mkdir -p "${LIVE_HOME}/.local/share/themes"
        cp -r "${THEME_SRC}" "${LIVE_HOME}/.local/share/themes/alinix-dracula" 2>/dev/null || true

        chown -R 1000:1000 "${LIVE_HOME}/.config" "${LIVE_HOME}/.themes" "${LIVE_HOME}/.local" 2>/dev/null || true
        log_ok "Tema GTK4 + Flatpak configurado para alinix-live"
    else
        log_warn "Tema alinix-dracula não encontrado em apps/themes/"
    fi

    # Garantir que Flatpak pode acessar ~/.themes (override global)
    mkdir -p "${BUILD_ROOT}/etc/flatpak/override"
    cat > "${BUILD_ROOT}/etc/flatpak/override/global" << 'EOF'
[Context]
filesystems=~/.themes:ro;~/.icons:ro;~/.local/share/themes:ro;~/.local/share/icons:ro;/usr/share/themes:ro;/usr/share/icons:ro
EOF

    # ── Casper ────────────────────────────────────────────────────────────────
    mkdir -p "${BUILD_ROOT}/etc"
    cat > "${BUILD_ROOT}/etc/casper.conf" << 'EOF'
# Casper — Alinix Live
export USERNAME="alinix-live"
export USERFULLNAME="Alinix Live"
export HOST="alinix"
export BUILD_SYSTEM="Alinix"
export FLAVOUR="Alinix"
EOF

    # Garantir que o initramfs-tools inclui o hook do Casper e módulos essenciais
    mkdir -p "${BUILD_ROOT}/etc/initramfs-tools/conf.d"
    cat > "${BUILD_ROOT}/etc/initramfs-tools/conf.d/alinix-live.conf" << 'EOF'
# Módulos necessários para o live boot
MODULES=most
COMPRESS=gzip
EOF

    # Módulos obrigatórios para montar a ISO e o squashfs
    mkdir -p "${BUILD_ROOT}/etc/initramfs-tools"
    if [[ ! -f "${BUILD_ROOT}/etc/initramfs-tools/modules" ]]; then
        touch "${BUILD_ROOT}/etc/initramfs-tools/modules"
    fi
    for mod in squashfs overlay isofs loop; do
        grep -q "^${mod}$" "${BUILD_ROOT}/etc/initramfs-tools/modules" || \
            echo "$mod" >> "${BUILD_ROOT}/etc/initramfs-tools/modules"
    done

    # Hook explícito para garantir overlay.ko no initramfs (necessário para Casper /cow)
    # MODULES=most às vezes não inclui overlay no kernel genérico do Ubuntu 24.04
    mkdir -p "${BUILD_ROOT}/etc/initramfs-tools/hooks"
    cat > "${BUILD_ROOT}/etc/initramfs-tools/hooks/alinix-overlay" << 'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
manual_add_modules overlay squashfs loop isofs
[ -d "${MODULESDIR}/kernel/fs/overlayfs" ] && copy_modules_dir kernel/fs/overlayfs || true
[ -d "${MODULESDIR}/kernel/fs/squashfs"  ] && copy_modules_dir kernel/fs/squashfs  || true
[ -d "${MODULESDIR}/kernel/fs/isofs"     ] && copy_modules_dir kernel/fs/isofs     || true

# kmod procura módulos em /lib/modules mas o initramfs moderno os coloca
# em /usr/lib/modules. Criar symlink para que modprobe encontre overlay.ko.
if [ ! -e "${DESTDIR}/lib/modules" ]; then
    mkdir -p "${DESTDIR}/lib"
    ln -s /usr/lib/modules "${DESTDIR}/lib/modules"
fi
EOF
    chmod 755 "${BUILD_ROOT}/etc/initramfs-tools/hooks/alinix-overlay"

    # Adicionar também overlayfs na lista de módulos (alias usado em alguns kernels)
    for mod in squashfs overlay overlayfs isofs loop; do
        grep -q "^${mod}$" "${BUILD_ROOT}/etc/initramfs-tools/modules" 2>/dev/null || \
            echo "$mod" >> "${BUILD_ROOT}/etc/initramfs-tools/modules"
    done

    # Patch do Casper: quando overlay/squashfs estão built-in (CONFIG_*=y),
    # não existe .ko e o modprobe retorna erro — o Casper interpreta isso como
    # "sem suporte" e entra em pânico. O workaround é um script que wraps o
    # modprobe e retorna 0 quando o módulo já está ativo no kernel.
    mkdir -p "${BUILD_ROOT}/etc/initramfs-tools/hooks"
    cat > "${BUILD_ROOT}/etc/initramfs-tools/hooks/alinix-modprobe-wrap" << 'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions

# Instalar wrapper de modprobe que trata módulos built-in como sucesso
copy_exec /bin/grep /bin
copy_exec /bin/cat  /bin

mkdir -p "${DESTDIR}/usr/local/sbin"
cat > "${DESTDIR}/usr/local/sbin/modprobe" << 'WRAP'
#!/bin/sh
# Wrapper: tenta modprobe real; se falhar, verifica se o módulo está built-in
/sbin/modprobe "$@" 2>/dev/null && exit 0
mod="${@##* }"
mod="${mod//-/_}"
grep -qx "$mod" /proc/modules 2>/dev/null && exit 0
grep -qw "$mod" /lib/modules/*/modules.builtin 2>/dev/null && exit 0
cat /sys/module/${mod}/initstate 2>/dev/null | grep -q "live" && exit 0
exit 1
WRAP
chmod 755 "${DESTDIR}/usr/local/sbin/modprobe"
EOF
    chmod 755 "${BUILD_ROOT}/etc/initramfs-tools/hooks/alinix-modprobe-wrap"

    log_ok "Modo live configurado."
}

# ==============================================================================
# STAGE 12: Configurações GSettings / Desktop UX
# ==============================================================================
stage_apply_desktop_ux() {
    log_stage "Stage 12 — Aplicando configurações de Desktop UX"

    # GSettings override de sistema (aplicado globalmente)
    mkdir -p "${BUILD_ROOT}/usr/share/glib-2.0/schemas"
    cat > "${BUILD_ROOT}/usr/share/glib-2.0/schemas/99_alinix.gschema.override" << 'EOF'
[org.gnome.desktop.wm.preferences]
button-layout='close,minimize,maximize:appmenu'
theme='alinix-dracula'

[org.gnome.desktop.interface]
color-scheme='prefer-dark'
cursor-theme='GoogleDot-Black'
icon-theme='Papirus-Dark'
gtk-theme='alinix-dracula'
font-name='Cantarell 11'

[org.gnome.desktop.peripherals.touchpad]
natural-scroll=true
tap-to-click=true
two-finger-scrolling-enabled=true

[org.gnome.mutter]
dynamic-workspaces=true

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/alinix/alinix-wallpaper-01.jpg'
picture-uri-dark='file:///usr/share/backgrounds/alinix/alinix-wallpaper-01.jpg'
picture-options='zoom'
primary-color='#0d001a'

[org.gnome.shell]
favorite-apps=['firefox.desktop', 'jexplorer.desktop', 'jterminal.desktop', 'com.alinix.ali.desktop', 'alinix-settings.desktop', 'alinix-installer.desktop', 'org.gnome.TextEditor.desktop']
enabled-extensions=['user-theme@gnome-shell-extensions.gcampax.github.com', 'erasshell@alinix', 'alinix-dock@alinix.osx', 'menu-global-gtk4@alinix.osx', 'wobbly-windows@weinberg.org']
welcome-dialog-last-shown-version='9999.0'

[org.gnome.shell.extensions.user-theme]
name='alinix-dracula'

[org.gnome.desktop.input-sources]
xkb-options=['altwin:ctrl_win']
EOF

    # Compilar schemas
    chroot "$BUILD_ROOT" /bin/bash -c "
        glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
    "

    # Script de autostart: ativa extensões Alinix na primeira sessão,
    # verificando quais estão de fato instaladas para evitar tela preta.
    mkdir -p "${BUILD_ROOT}/etc/xdg/autostart"
    cat > "${BUILD_ROOT}/etc/xdg/autostart/alinix-enable-extensions.desktop" << 'AUTOSTART'
[Desktop Entry]
Type=Application
Name=Alinix Enable Extensions
Exec=/usr/local/bin/alinix-enable-extensions
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Phase=Application
AUTOSTART

    cat > "${BUILD_ROOT}/usr/local/bin/alinix-enable-extensions" << 'ENABLE_EXT'
#!/usr/bin/env bash
# Ativa extensões Alinix na primeira sessão, apenas as que estão instaladas.
# Roda via autostart para evitar tela preta se uma extensão falhar no build.

MARKER="$HOME/.local/share/alinix-extensions-enabled"
[[ -f "$MARKER" ]] && exit 0

sleep 3  # Esperar o shell iniciar completamente

EXT_DIRS=(
    "/usr/share/gnome-shell/extensions"
    "$HOME/.local/share/gnome-shell/extensions"
)

_ext_installed() {
    local uuid="$1"
    for d in "${EXT_DIRS[@]}"; do
        [[ -f "$d/$uuid/metadata.json" ]] && return 0
    done
    return 1
}

EXTS=()
for uuid in \
    "user-theme@gnome-shell-extensions.gcampax.github.com" \
    "erasshell@alinix" \
    "alinix-dock@alinix.osx" \
    "menu-global-gtk4@alinix.osx" \
    "menu-global@alinix.osx" \
    "wobbly-windows@weinberg.org"; do
    _ext_installed "$uuid" && EXTS+=("$uuid")
done

if [[ ${#EXTS[@]} -gt 0 ]]; then
    LIST="["
    for i in "${!EXTS[@]}"; do
        [[ $i -gt 0 ]] && LIST+=","
        LIST+="'${EXTS[$i]}'"
    done
    LIST+="]"
    gsettings set org.gnome.shell enabled-extensions "$LIST"
fi

# Aplicar tema GTK4 no ~/.config/gtk-4.0/ se ainda não estiver lá
GTK4_CSS="$HOME/.config/gtk-4.0/gtk.css"
if [[ ! -f "$GTK4_CSS" ]] && [[ -f "/usr/share/themes/alinix-dracula/gtk-4.0/gtk.css" ]]; then
    mkdir -p "$HOME/.config/gtk-4.0"
    cp /usr/share/themes/alinix-dracula/gtk-4.0/gtk.css "$GTK4_CSS"
    [[ -f "/usr/share/themes/alinix-dracula/gtk-4.0/gtk-dark.css" ]] && \
        cp /usr/share/themes/alinix-dracula/gtk-4.0/gtk-dark.css "$HOME/.config/gtk-4.0/gtk-dark.css" || true
    [[ -d "/usr/share/themes/alinix-dracula/gtk-4.0/assets" ]] && \
        cp -r /usr/share/themes/alinix-dracula/gtk-4.0/assets "$HOME/.config/gtk-4.0/assets" || true
fi

# Aplicar tema user-theme (GNOME Shell) via gsettings
if _ext_installed "user-theme@gnome-shell-extensions.gcampax.github.com"; then
    gsettings set org.gnome.shell.extensions.user-theme name 'alinix-dracula' 2>/dev/null || true
fi

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
ENABLE_EXT
    chmod +x "${BUILD_ROOT}/usr/local/bin/alinix-enable-extensions"

    # ── Instalar fonte AlinixLogo (U+E000 = logo) ────────────────────────────
    mkdir -p "${BUILD_ROOT}/usr/share/fonts/opentype/alinix"
    cp "${SCRIPT_DIR}/sys/assets/AlinixLogo-Regular.otf" \
       "${BUILD_ROOT}/usr/share/fonts/opentype/alinix/" 2>/dev/null || true
    chroot "$BUILD_ROOT" /bin/bash -c "
        fc-cache -f /usr/share/fonts/opentype/alinix/ 2>/dev/null || true
    "

    log_ok "Desktop UX configurado."
    log_ok "Script alinix-enable-extensions criado (ativa extensões com segurança no primeiro boot)."
}

# ==============================================================================
# STAGE 13: Diretórios XDG e skel finalizado
# ==============================================================================
stage_finalize_skel() {
    log_stage "Stage 13 — Finalizando skel e diretórios de usuário"

    local SKEL="${BUILD_ROOT}/etc/skel"

    # Garantir que apenas Desktop, Documentos e Downloads são criados
    mkdir -p "${SKEL}/Desktop" "${SKEL}/Documentos" "${SKEL}/Downloads"

    # xdg-user-dirs (já feito no fhs-map.sh, mas garantir)
    mkdir -p "${BUILD_ROOT}/etc/xdg"
    cat > "${BUILD_ROOT}/etc/xdg/user-dirs.defaults" << 'EOF'
DESKTOP=Desktop
DOWNLOAD=Downloads
TEMPLATES=
PUBLICSHARE=
DOCUMENTS=Documentos
MUSIC=
PICTURES=
VIDEOS=
EOF

    # Diretórios de repo do alipack
    mkdir -p "${BUILD_ROOT}/Etc/Repo/ALI"
    mkdir -p "${BUILD_ROOT}/Etc/Repo/APT"
    mkdir -p "${BUILD_ROOT}/Etc/Repo/AUR"

    # Criar source.list iniciais
    echo "# Repositórios ALI (nativos Alinix)" > "${BUILD_ROOT}/Etc/Repo/ALI/source.list"
    echo "# Repositórios APT (Debian/Ubuntu)" > "${BUILD_ROOT}/Etc/Repo/APT/source.list"
    echo "# Repositórios AUR (Arch User Repository)" > "${BUILD_ROOT}/Etc/Repo/AUR/source.list"

    log_ok "Skel e diretórios finalizados."
}

# ==============================================================================
# STAGE 13.5: Gerar initramfs final dentro do chroot
# Deve rodar depois de todos os stages que modificam o chroot.
# O initramfs precisa incluir: hook Casper, módulos squashfs/overlay/isofs,
# tema Plymouth. Por isso roda por último, antes de gerar a ISO.
# ==============================================================================
stage_build_initramfs() {
    log_stage "Stage 13.5 — Gerando initramfs final (Casper + Plymouth)"

    local KVER
    if [[ "$KERNEL_MODE" == "generic" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | grep -E "generic|amd64" | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    elif [[ "$KERNEL_MODE" == "lix7" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | grep -E "vmlinuz-7" | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    elif [[ "$KERNEL_MODE" == "lix6" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | grep -E "vmlinuz-6" | grep -v "generic" | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    fi

    if [[ -z "$KVER" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    fi

    if [[ -z "$KVER" ]]; then
        log_error "Kernel não encontrado em ${BUILD_ROOT}/boot"
        exit 1
    fi
    log_info "Kernel detectado: $KVER"

    # Remover o initramfs Rust copiado pelo Stage 5.5 — o update-initramfs
    # com -c falha se o arquivo já existe, deixando o init Rust no lugar do Casper.
    rm -f "${BUILD_ROOT}/boot/initrd.img-${KVER}"
    log_info "initramfs Rust removido — será substituído pelo Casper"

    chroot "$BUILD_ROOT" /bin/bash -c "
        set -e
        # Verificar se casper está instalado
        if ! dpkg -l casper 2>/dev/null | grep -q '^ii'; then
            echo 'AVISO: casper não instalado — tentando instalar...'
            apt-get install -y --no-install-recommends casper 2>/dev/null || true
        fi

        # Garantir que os módulos essenciais para live boot estão listados
        for mod in squashfs overlay isofs loop; do
            grep -q \"^\${mod}\$\" /etc/initramfs-tools/modules 2>/dev/null \
                || echo \"\$mod\" >> /etc/initramfs-tools/modules
        done

        # Criar initramfs limpo com Casper integrado
        # Usar -c (create) pois removemos o arquivo acima
        update-initramfs -c -k ${KVER} 2>&1

        ls -lh /boot/initrd.img-* 2>/dev/null || true
    "

    # Verificar que o initramfs foi gerado e tem tamanho razoável (>10 MB = tem Casper)
    local INITRD_SIZE
    INITRD_SIZE=$(du -sm "${BUILD_ROOT}/boot/initrd.img-${KVER}" 2>/dev/null | cut -f1 || echo 0)
    if [[ "$INITRD_SIZE" -lt 10 ]]; then
        log_warn "initramfs gerado parece pequeno (${INITRD_SIZE} MB) — pode ser o init Rust sem Casper"
        log_warn "Verifique se o casper está instalado no chroot e os módulos squashfs/overlay/isofs"
    else
        log_ok "initramfs Casper gerado: ${INITRD_SIZE} MB"
    fi

    log_ok "initramfs final gerado: ${BUILD_ROOT}/boot/initrd.img-${KVER}"
}

# ==============================================================================
# STAGE 14: Gerar ISO com Casper + GRUB
# ==============================================================================
stage_generate_iso() {
    log_stage "Stage 14 — Gerando ISO bootável Alinix"

    local WORK="${SCRIPT_DIR}/sys/build/workspace/iso-stage"

    rm -rf "$WORK"
    mkdir -p "$WORK/casper" "$WORK/boot/grub" "$WORK/.disk" "$DIST_DIR"

    # ── 14.1 Copiar kernel ───────────────────────────────────────────────────
    local KVER
    if [[ "$KERNEL_MODE" == "generic" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | grep -E "generic|amd64" | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    elif [[ "$KERNEL_MODE" == "lix7" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | grep -E "vmlinuz-7" | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    elif [[ "$KERNEL_MODE" == "lix6" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | grep -E "vmlinuz-6" | grep -v "generic" | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    fi

    if [[ -z "$KVER" ]]; then
        KVER=$(find "${BUILD_ROOT}/boot" -maxdepth 1 -name "vmlinuz-*" 2>/dev/null \
               | sort -V | tail -1 | xargs -I{} basename {} | sed 's/vmlinuz-//')
    fi

    local KERNEL="${BUILD_ROOT}/boot/vmlinuz-${KVER}"
    if [[ ! -f "$KERNEL" ]]; then
        log_error "Kernel não encontrado: $KERNEL"
        exit 1
    fi
    cp "$KERNEL" "$WORK/casper/vmlinuz"
    log_ok "Kernel: $(basename "$KERNEL")"

    # ── 14.1.2 Gerar initramfs Rust (alinix-init) ───────────────────────────
    log_info "Compilando e empacotando initramfs alinix-init (Rust)..."
    local INITRD_TMP INITRD_OUT="$WORK/casper/initrd"
    # Gravar em dir do usuário real para evitar problema de permissão do /tmp (root)
    local _USER_TMP="/home/${SUDO_USER:-root}/tmp-alinix-initrd"
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo -u "$SUDO_USER" mkdir -p "$_USER_TMP"
        INITRD_TMP="$_USER_TMP/initrd.img"
        sudo -u "$SUDO_USER" env PATH="$PATH" HOME="/home/$SUDO_USER" \
            bash "${SCRIPT_DIR}/apps/alinix-init/build-initramfs.sh" --output "$INITRD_TMP"
    else
        INITRD_TMP="/tmp/alinix-initrd.img"
        bash "${SCRIPT_DIR}/apps/alinix-init/build-initramfs.sh" --output "$INITRD_TMP"
    fi
    mv "$INITRD_TMP" "$INITRD_OUT"
    [[ -n "${SUDO_USER:-}" ]] && rm -rf "$_USER_TMP" || true
    log_ok "Initrd alinix-init gerado ($(du -sh "$INITRD_OUT" | awk '{print $1}'))"

    # ── 14.2 Criar squashfs ──────────────────────────────────────────────────
    log_info "Criando filesystem.squashfs (xz) — isso pode levar vários minutos..."
    # Garantir que os diretórios de mount point existem no chroot antes de empacotar
    # O systemd precisa encontrá-los no rootfs para montar os pseudo-filesystems
    for _dir in proc sys dev run tmp; do
        mkdir -p "${BUILD_ROOT}/${_dir}"
    done
    # Limpar conteúdo de /dev e /run (serão populados pelo kernel no boot)
    find "${BUILD_ROOT}/dev" -mindepth 1 -delete 2>/dev/null || true
    find "${BUILD_ROOT}/run" -mindepth 1 -delete 2>/dev/null || true

    mksquashfs "$BUILD_ROOT" "$WORK/casper/filesystem.squashfs" \
        -e boot \
        -e tmp \
        -noappend \
        -no-xattrs \
        -comp xz \
        -mem 512M
    log_ok "filesystem.squashfs criado ($(du -sh "$WORK/casper/filesystem.squashfs" | awk '{print $1}'))"

    # ── 14.3 Metadados do disco ──────────────────────────────────────────────
    echo "Alinix Live" > "$WORK/.disk/info"
    echo "https://alinix.dev" > "$WORK/.disk/release_notes_url"

    # filesystem.manifest
    chroot "$BUILD_ROOT" dpkg-query -W --showformat='${Package} ${Version}\n' \
        > "$WORK/casper/filesystem.manifest" 2>/dev/null || true

    # filesystem.size
    du -sx --block-size=1 "$BUILD_ROOT" | cut -f1 > "$WORK/casper/filesystem.size"

    # ── 14.4 GRUB config ────────────────────────────────────────────────────
    # Copiar tema do GRUB para a ISO
    mkdir -p "$WORK/boot/grub/themes"
    cp -r "${SCRIPT_DIR}/sys/assets/grub-theme/alinix" "$WORK/boot/grub/themes/"

    cat > "$WORK/boot/grub/grub.cfg" << 'GRUBCFG'
set default=0
set timeout=5

insmod all_video
insmod gfxterm
insmod png
insmod font

if loadfont unicode ; then
  set gfxmode=auto
  terminal_output gfxterm
fi

set theme=($root)/boot/grub/themes/alinix/theme.txt

menuentry "Alinix — Iniciar Live" --class alinix {
    linux /casper/vmlinuz quiet splash plymouth.use-simpledrm
    initrd /casper/initrd
}

menuentry "Alinix — Iniciar Live (modo seguro)" --class linux {
    linux /casper/vmlinuz nomodeset plymouth.enable=0
    initrd /casper/initrd
}

menuentry "Alinix — Iniciar Live (debug)" --class debian {
    linux /casper/vmlinuz ignore_loglevel
    initrd /casper/initrd
}

menuentry "Configurações UEFI" --class settings {
    fwsetup
}
GRUBCFG

    # ── 14.5 Gerar ISO ──────────────────────────────────────────────────────
    log_info "Gerando ISO híbrida UEFI + BIOS..."
    grub-mkrescue -o "$ISO_OUT" "$WORK" \
        -volid "ALINIX_LIVE" \
        -J -joliet-long \
        -r

    local SIZE
    SIZE=$(du -sh "$ISO_OUT" | awk '{print $1}')

    # Limpar staging
    rm -rf "$WORK"

    echo ""
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✓ ISO Alinix gerada com sucesso!${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Arquivo:${NC}  $ISO_OUT"
    echo -e "  ${BOLD}Tamanho:${NC} $SIZE"
    echo ""
    echo -e "  ${BOLD}Como usar:${NC}"
    echo -e "    • GNOME Boxes  → Criar nova VM → Selecionar $ISO_OUT"
    echo -e "    • VirtualBox   → Nova VM → Disco: $ISO_OUT"
    echo -e "    • USB          → dd if=$ISO_OUT of=/dev/sdX bs=4M status=progress"
    echo ""
}

# ==============================================================================
# STAGE 15: Fixups de userspace (snapd, casper-md5check, GDM Wayland)
# ==============================================================================
stage_fixup_userspace() {
    log_stage "Stage 15 — Fixups de userspace"

    chroot "$BUILD_ROOT" /bin/bash <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive

# ── Remover snapd (causa 25s+ de delay no boot) ──────────────────────────────
if dpkg -l snapd 2>/dev/null | grep -q '^ii'; then
    apt-get purge -y snapd 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
fi
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /root/snap 2>/dev/null || true
cat > /etc/apt/preferences.d/no-snapd << 'EOF'
Package: snapd
Pin: release *
Pin-Priority: -1
EOF

# ── Remover apps GNOME indesejados (substituídos por apps Alinix) ─────────────
# nautilus      → substituído por JExplorer
# gnome-terminal → substituído por JTerminal
# gnome-control-center → substituído por alinix-settings
# yelp          → documentação GNOME desnecessária no live
for pkg in \
    nautilus nautilus-extension-gnome-terminal \
    gnome-terminal gnome-terminal-data \
    gnome-control-center gnome-control-center-data \
    yelp yelp-xsl \
    totem totem-common \
    rhythmbox rhythmbox-data \
    cheese simple-scan \
    gnome-online-accounts; do
    dpkg -l "$pkg" 2>/dev/null | grep -q '^ii' && \
        apt-get purge -y "$pkg" 2>/dev/null || true
done
apt-get autoremove -y 2>/dev/null || true

    # ── VirtualBox Guest Additions (se kernel genérico) ──────────────────────
    # VMSVGA com 3D acceleration exige vboxvideo e vboxguest.
    # DKMS compila o módulo contra o kernel instalado no chroot.
    apt-get install -y --no-install-recommends \
        virtualbox-guest-utils virtualbox-guest-x11 2>/dev/null || true

    # ── Impedir que udev/udisks consultem o CDROM durante boot live ────────────
    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/60-cdrom_id.rules << 'EOF'
# Pular polling do CDROM para a mídia live (evita I/O error no sr0)
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sr0", ENV{UDISKS_IGNORE}="1"
EOF

# ── Desabilitar casper-md5check (falha por ausência de md5sum.txt na ISO) ───
systemctl disable casper-md5check.service 2>/dev/null || true
if [ -f /lib/systemd/system/casper-md5check.service ]; then
    ln -sf /dev/null /etc/systemd/system/casper-md5check.service
fi


# ── Remover serviços desnecessários para live boot ────────────────────────────
for svc in apt-daily.service apt-daily-upgrade.service \
            apt-daily.timer apt-daily-upgrade.timer \
            e2scrub_all.timer fstrim.timer motd-news.timer \
            systemd-tmpfiles-clean.timer dpkg-db-backup.timer; do
    systemctl disable "$svc" 2>/dev/null || true
    ln -sf /dev/null "/etc/systemd/system/$svc" 2>/dev/null || true
done

echo "Fixups aplicados."
CHROOT

    log_ok "Fixups de userspace concluídos."
}

# ==============================================================================
# Execução principal
# ==============================================================================

trap umount_chroot EXIT

case "$MODE" in
    full)
        if [[ "$RECOMPILE_KERNEL" == "y" && "$KERNEL_MODE" != "generic" ]]; then
            case "$KERNEL_MODE" in
                lix7) compile_kernel "$LIX7_SRC" "7.x" ;;
                *)    compile_kernel "$LIX6_SRC" "6.x" ;;
            esac
        fi

        verify_host_deps
        stage_debootstrap
        mount_chroot
        stage_configure_system
        stage_install_packages
        stage_install_drivers
        stage_install_lix_kernel
        stage_apply_fhs
        stage_setup_zsh
        stage_install_plymouth
        stage_setup_permissions
        stage_clone_apps
        stage_install_apps
        stage_setup_live
        stage_apply_desktop_ux
        stage_finalize_skel
        stage_fixup_userspace
        stage_build_initramfs
        umount_chroot
        stage_generate_iso
        ;;
    chroot)
        mount_chroot
        log_info "Entrando no chroot. Digite 'exit' para sair."
        chroot "$BUILD_ROOT" /bin/bash
        ;;
    iso-only)
        # Recompilar kernel se pedido
        if [[ "$OPT_RECOMPILE_KERNEL" -eq 1 && "$KERNEL_MODE" != "generic" ]]; then
            case "$KERNEL_MODE" in
                lix7) compile_kernel "$LIX7_SRC" "7.x" ;;
                *)    compile_kernel "$LIX6_SRC" "6.x" ;;
            esac
        fi

        if [[ ! -d "${BUILD_ROOT}/usr" ]]; then
            log_error "Nenhum build encontrado em $BUILD_ROOT"
            log_error "Execute primeiro: sudo ./setup.sh"
            exit 1
        fi

        mount_chroot

        # --fixup: corrige snapd, casper-md5check, GDM Wayland no chroot
        if [[ "$OPT_FIXUP" -eq 1 ]]; then
            stage_fixup_userspace
        fi

        # --initrd: instala kernel e regera initramfs Rust
        if [[ "$OPT_INITRD" -eq 1 ]]; then
            stage_install_lix_kernel
            stage_build_initramfs
        fi

        umount_chroot
        stage_generate_iso
        ;;
esac

log_ok "Concluído!"
