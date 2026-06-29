#!/usr/bin/env bash
# Alinix — Configuração de montagem de volumes e suporte a Filesystems (Stage 5)
# Requisitos: #9 (/Volumes) e #12 (ext4, exFAT, FAT32, NTFS, APFS)
set -euo pipefail

ALINIX_ROOT="${ALINIX_ROOT:-}"
if [ -z "$ALINIX_ROOT" ]; then
  echo "Aviso: ALINIX_ROOT não definido, instalando no sistema local ativo."
  R=""
else
  R="$ALINIX_ROOT"
  echo "Configurando filesystems no chroot: $R"
fi

# 1. Garantir existência de /Volumes e links FHS
echo ">> Provisionando diretórios de montagem e symlinks..."
install -d "$R/Volumes"
if [ ! -L "$R/mnt" ]; then ln -sfn /Volumes "$R/mnt"; fi
if [ ! -L "$R/media" ]; then ln -sfn /Volumes "$R/media"; fi

# 2. Configurar Regra do Udev para udisks2 montar em /Volumes (via /media -> /Volumes)
# Ao definir UDISKS_FILESYSTEM_SHARED=1, o udisks2 passa a montar em /media/<label>
# em vez de /run/media/$USER/<label>. Como /media aponta para /Volumes, cai no local correto!
echo ">> Configurando regras do udev para udisks2 (montagens automáticas em /Volumes)..."
install -d "$R/etc/udev/rules.d"
cat << 'EOF' > "$R/etc/udev/rules.d/99-alinix-volumes.rules"
# Força o udisks2 a usar o diretório /media compartilhado (que aponta para /Volumes)
SUBSYSTEM=="block", ENV{UDISKS_FILESYSTEM_SHARED}="1"
EOF

# 3. Configurar módulo do kernel para NTFS (ntfs3)
# Opcional: blacklist do módulo antigo 'ntfs' se houver conflito com o novo driver Paragon
echo ">> Configurando preferências do NTFS (ntfs3 Paragon)..."
install -d "$R/etc/modprobe.d"
cat << 'EOF' > "$R/etc/modprobe.d/ntfs3.conf"
# Garante o uso do driver ntfs3 Paragon para leitura e escrita nativas
alias fs-ntfs ntfs3
EOF

# 4. Configurar helper de montagem APFS (apfs-fuse)
# Cria um script de wrapper de montagem para o mount clássico entender 'mount -t apfs'
echo ">> Criando mount helper para APFS (/sbin/mount.apfs)..."
install -d "$R/sbin"
cat << 'EOF' > "$R/sbin/mount.apfs"
#!/usr/bin/env bash
# mount.apfs — Helper de compatibilidade para montagem de volumes APFS usando apfs-fuse
set -eu

DEVICE="$1"
MOUNT_POINT="$2"
shift 2

# Extrai opções adicionais de montagem, se houver
OPTS=""
while geto getopts "o:" opt; do
  case "$opt" in
    o) OPTS="$OPTARG" ;;
    *) ;;
  esac
done

# APFS via FUSE só é montado de forma segura em Read-Only (ro) por padrão
echo "Mounting APFS volume $DEVICE read-only in $MOUNT_POINT"
exec apfs-fuse -o ro,allow_other "${DEVICE}" "${MOUNT_POINT}"
EOF
chmod +x "$R/sbin/mount.apfs"

echo ">> Configurações de filesystems injetadas com sucesso."
