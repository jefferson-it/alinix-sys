#!/bin/bash
# =============================================================================
# Instalador do tema Plymouth para Alinix OS
# Descrição: Converte o logo SVG, copia o tema para o diretório do Plymouth,
#            define como tema padrão e atualiza o initramfs.
# =============================================================================

set -e

# ─── Cores para saída no terminal ────────────────────────────────────────────
ROXO='\033[0;35m'
VERDE='\033[0;32m'
VERMELHO='\033[0;31m'
RESET='\033[0m'

# ─── Caminhos ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THEME_SRC="$SCRIPT_DIR/alinix-theme"
LOGO_SVG="$PROJECT_ROOT/sys/assets/logo.svg"
LOGO_PNG="$THEME_SRC/logo.png"
THEME_DEST="/usr/share/plymouth/themes/alinix-theme"

# ─── Verificação de privilégios de root ──────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${VERMELHO}[ERRO]${RESET} Este script deve ser executado como root (sudo)."
    exit 1
fi

echo -e "${ROXO}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${ROXO}║       Instalador do Tema Plymouth - Alinix OS       ║${RESET}"
echo -e "${ROXO}╚══════════════════════════════════════════════════════╝${RESET}"
echo ""

# ─── Etapa 1: Verificar dependências ─────────────────────────────────────────
echo -e "${ROXO}[1/5]${RESET} Verificando dependências..."

if ! command -v rsvg-convert &> /dev/null; then
    echo -e "  → Instalando librsvg2-bin (rsvg-convert)..."
    apt-get install -y librsvg2-bin > /dev/null 2>&1
fi

if ! command -v plymouth-set-default-theme &> /dev/null; then
    echo -e "  → Instalando plymouth..."
    apt-get install -y plymouth plymouth-themes > /dev/null 2>&1
fi

echo -e "  ${VERDE}✓ Dependências satisfeitas${RESET}"

# ─── Etapa 2: Converter logo SVG para PNG ────────────────────────────────────
echo -e "${ROXO}[2/5]${RESET} Convertendo logo.svg para logo.png..."

if [ ! -f "$LOGO_SVG" ]; then
    echo -e "  ${VERMELHO}[ERRO]${RESET} Arquivo não encontrado: $LOGO_SVG"
    exit 1
fi

# Converte com dimensão adequada para tela de boot (256x256)
# O SVG usa fill="currentColor" — forçar branco via CSS para contrastar com fundo preto
rsvg-convert -w 256 -h 256 \
    --stylesheet <(echo 'svg { color: white; }') \
    "$LOGO_SVG" -o "$LOGO_PNG" 2>/dev/null || \
rsvg-convert -w 256 -h 256 "$LOGO_SVG" -o "$LOGO_PNG"
echo -e "  ${VERDE}✓ Logo convertido com sucesso${RESET}"

# ─── Etapa 3: Copiar tema para o diretório do Plymouth ───────────────────────
echo -e "${ROXO}[3/5]${RESET} Instalando tema no diretório do Plymouth..."

# Remove instalação anterior se existir
if [ -d "$THEME_DEST" ]; then
    rm -rf "$THEME_DEST"
fi

# Cria diretório e copia os arquivos do tema
mkdir -p "$THEME_DEST"
cp "$THEME_SRC/alinix-theme.plymouth" "$THEME_DEST/"
cp "$THEME_SRC/alinix-theme.script" "$THEME_DEST/"
cp "$LOGO_PNG" "$THEME_DEST/"

echo -e "  ${VERDE}✓ Tema instalado em $THEME_DEST${RESET}"

# ─── Etapa 4: Definir como tema padrão ───────────────────────────────────────
echo -e "${ROXO}[4/5]${RESET} Definindo alinix-theme como tema padrão..."

plymouth-set-default-theme alinix-theme

# Garantir que o /etc/plymouth/plymouthd.conf está correto
mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf << 'PLYMCONF'
[Daemon]
Theme=alinix-theme
ShowDelay=0
DeviceTimeout=8
PLYMCONF

# Garantir que o GRUB passa os parâmetros corretos E que plymouth.enable=0
# desabilita de verdade (sem isso, ESC/Tab são ignorados pelo Plymouth)
if [ -f /etc/default/grub ]; then
    # Adicionar 'plymouth.use-simpledrm' para forçar modo compatível com VMs
    if ! grep -q "plymouth.use-simpledrm" /etc/default/grub; then
        sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 plymouth.use-simpledrm"/' /etc/default/grub 2>/dev/null || true
    fi
    update-grub 2>/dev/null || true
fi

echo -e "  ${VERDE}✓ Tema definido como padrão${RESET}"

# ─── Etapa 5: Atualizar initramfs ────────────────────────────────────────────
echo -e "${ROXO}[5/5]${RESET} Atualizando initramfs (pode levar alguns segundos)..."

# Rebuild completo com o tema novo incluído
update-initramfs -u -k all

echo -e "  ${VERDE}✓ Initramfs atualizado com sucesso${RESET}"

# ─── Conclusão ───────────────────────────────────────────────────────────────
echo ""
echo -e "${VERDE}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${VERDE}║     Tema Plymouth instalado com sucesso! 🎉         ║${RESET}"
echo -e "${VERDE}║     Reinicie para visualizar o novo tema de boot.   ║${RESET}"
echo -e "${VERDE}╚══════════════════════════════════════════════════════╝${RESET}"
