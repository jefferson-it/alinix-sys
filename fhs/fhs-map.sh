#!/usr/bin/env bash
# Alinix — aplica a hierarquia de arquivos Alinix sobre uma raiz LFS.
# Pré-requisito: a raiz já deve ter merged-usr (bin/sbin/lib -> usr). LFS faz isso.
# Roda no Stage 4 do build, dentro do chroot, com ALINIX_ROOT = raiz do sistema.
#
# SEGURANÇA: por padrão RECUSA rodar em "/" (sua máquina de desenvolvimento).
#   uso:  ALINIX_ROOT=/mnt/lfs  fhs/fhs-map.sh
set -euo pipefail

ALINIX_ROOT="${ALINIX_ROOT:-}"
if [ -z "$ALINIX_ROOT" ]; then
  echo "erro: defina ALINIX_ROOT (ex.: ALINIX_ROOT=/mnt/lfs $0). Recuso rodar sem alvo." >&2
  exit 1
fi
if [ "$ALINIX_ROOT" = "/" ] && [ "${FORCE_ROOT:-0}" != "1" ]; then
  echo "erro: ALINIX_ROOT=/ aplicaria na máquina HOST. De propósito? FORCE_ROOT=1." >&2
  exit 1
fi

R="$ALINIX_ROOT"
echo ">> aplicando Alinix FHS em: $R"

# diretórios reais que a hierarquia Alinix precisa
install -d "$R/home" "$R/etc/skel" "$R/Volumes" "$R/Progs" "$R/usr/lib"

# Garante que ao gerar a Home do usuário, só sejam criadas as pastas Desktop, Documentos e Downloads
install -d "$R/etc/skel/Desktop" "$R/etc/skel/Documentos" "$R/etc/skel/Downloads"

# Configura o xdg-user-dirs do sistema para mapear e gerar apenas essas 3 pastas
install -d "$R/etc/xdg"
cat << 'EOF' > "$R/etc/xdg/user-dirs.defaults"
DESKTOP=Desktop
DOWNLOAD=Downloads
TEMPLATES=
PUBLICSHARE=
DOCUMENTS=Documentos
MUSIC=
PICTURES=
VIDEOS=
EOF

# /Library: diretório real com sub-symlinks por largura de palavra (req #5)
install -d "$R/Library"
ln -sfn /usr/lib "$R/Library/64"
if [ -d "$R/usr/lib32" ]; then ln -sfn /usr/lib32 "$R/Library/32"; fi

# /Users: diretório real para mount bind (req #3)
install -d "$R/Users"
if [ -f "$R/etc/fstab" ]; then
  if ! grep -q "/Users" "$R/etc/fstab"; then
    echo -e "\n# Mapeamento do diretório de usuários\n/home /Users none bind 0 0" >> "$R/etc/fstab"
  fi
fi

# nomes Alinix no topo -> FHS real (alvos ABSOLUTOS: resolvem quando $R for a raiz)
ln -sfn /usr/bin  "$R/Exec"    # req #6

# montagens: /Volumes é o lar; mnt/media apontam pra ele (req #9)
ln -sfn /Volumes "$R/mnt"
ln -sfn /Volumes "$R/media"

# apps universais: /opt vira /Progs (req #10)
ln -sfn /Progs "$R/opt"

# esconder os nomes FHS minúsculos no file manager (estilo macOS Finder)
printf '%s\n' bin sbin lib lib64 usr etc var opt mnt media srv run proc sys dev tmp boot \
  > "$R/.hidden"

echo ">> Alinix FHS aplicada. 'ls /' vai mostrar: Users Library Exec Volumes Progs"

