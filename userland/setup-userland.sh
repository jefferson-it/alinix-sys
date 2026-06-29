#!/usr/bin/env bash
# Alinix — Script de setup do uutils (Rust coreutils) (Stage 4)
# Requisito: #1 (Compatibilidade com coreutils)
set -euo pipefail

ALINIX_ROOT="${ALINIX_ROOT:-}"
if [ -z "$ALINIX_ROOT" ]; then
  echo "Aviso: ALINIX_ROOT não definido, instalando no sistema local ativo."
  R=""
else
  R="$ALINIX_ROOT"
  echo "Instalando uutils no chroot: $R"
fi

# Lista de utilitários clássicos do coreutils que serão substituídos pelo uutils
COREUTILS=(
  arch base32 base64 basename cat chcon chgrp chmod chown chroot cksum comm cp
  csplit cut date dd df dir dircolors dirname du echo env expand expr factor false
  fmt fold groups head hostid id install join link ln logname ls md5sum mkdir mkfifo
  mknod mktemp mv nice nl nohop nproc numfmt od paste pathchk pinky pr printenv
  printf ptx pwd readlink realpath rm rmdir runcon seq sha1sum sha224sum sha256sum
  sha384sum sha512sum shred shuf sleep sort split stat stty sum sync tac tail tee
  test timeout touch tr true truncate tsort tty uname unexpand uniq unlink uptime
  users vdir wc who whoami yes
)

# 1. Preparar diretório de backup do GNU Coreutils real
echo ">> Criando diretório de compatibilidade para o GNU Coreutils original..."
install -d "$R/usr/lib/gnu-coreutils/bin"

# Links de compatibilidade Alinix-FHS (resolvido dinamicamente via /usr/lib/gnu-coreutils/bin)


# 2. Mover utilitários GNU originais para o diretório de compatibilidade (backup)
echo ">> Movendo binários GNU originais para backup..."
for cmd in "${COREUTILS[@]}"; do
  if [ -f "$R/usr/bin/$cmd" ] && [ ! -L "$R/usr/bin/$cmd" ]; then
    mv "$R/usr/bin/$cmd" "$R/usr/lib/gnu-coreutils/bin/$cmd"
  elif [ -f "$R/bin/$cmd" ] && [ ! -L "$R/bin/$cmd" ]; then
    # Caso o merged-usr não esteja 100% completo no momento
    mv "$R/bin/$cmd" "$R/usr/lib/gnu-coreutils/bin/$cmd"
  fi
done

# 3. Compilação/Instalação do uutils multicall (Se estivermos no build do LFS)
# NOTA: O binário "coreutils" do uutils é gerado via Cargo.
# Se o binário 'coreutils' compilado em Rust estiver disponível em /tmp/uutils, nós o instalamos.
if [ -f "$R/tmp/uutils-src/target/release/coreutils" ]; then
  echo ">> Instalando executável multicall uutils Rust em /usr/bin/coreutils..."
  cp "$R/tmp/uutils-src/target/release/coreutils" "$R/usr/bin/coreutils"
  chmod 755 "$R/usr/bin/coreutils"
else
  echo ">> Usando stub/stub de simulação para /usr/bin/coreutils..."
  # Stub temporário para validação do chroot antes da compilação real do Rust no Stage 4
  cat << 'EOF' > "$R/usr/bin/coreutils"
#!/bin/bash
# uutils multicall mock / stub do Alinix
cmd="${0##*/}"
if [ "$cmd" = "coreutils" ]; then
  echo "uutils coreutils v0.0.1 (stub)"
  exit 0
fi
exec /usr/lib/gnu-coreutils/bin/"$cmd" "$@"
EOF
  chmod 755 "$R/usr/bin/coreutils"
fi

# 4. Criar symlinks no /usr/bin apontando para o multicall do uutils
echo ">> Criando symlinks dos comandos coreutils para o uutils..."
for cmd in "${COREUTILS[@]}"; do
  # Remove symlink ou stub anterior
  rm -f "$R/usr/bin/$cmd"
  # Aponta para o executável do uutils
  ln -sf coreutils "$R/usr/bin/$cmd"
done

# 5. Configurar o PATH padrão no /etc/profile para priorizar /Exec e /usr/bin
echo ">> Configurando PATH global no /etc/profile..."
install -d "$R/etc"
if [ -f "$R/etc/profile" ]; then
  if ! grep -q "/Exec" "$R/etc/profile"; then
    echo 'export PATH=/Exec:/usr/bin:/usr/local/bin:$PATH' >> "$R/etc/profile"
  fi
else
  cat << 'EOF' > "$R/etc/profile"
# /etc/profile - Configuração global de inicialização de shell do Alinix
export PATH=/Exec:/usr/bin:/usr/local/bin:$PATH
export PS1='Alinix:\w\$ '
EOF
fi

echo ">> Configuração do uutils Rust concluída com sucesso."
