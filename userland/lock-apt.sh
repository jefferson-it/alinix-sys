#!/usr/bin/env bash
# Alinix — bloqueia apt/dpkg para usuários não-root.
# O gerenciador público do Alinix é o alipack; apt é reservado para manutenção root.
# Uso: lock-apt.sh [--root <chroot>]
set -euo pipefail

ROOT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root|-r) ROOT="$2"; shift 2 ;;
        *) echo "uso: $0 [--root <chroot>]"; exit 1 ;;
    esac
done

# 1. Remover permissão de execução do apt real para "others"
for bin in apt apt-get apt-cache apt-mark dpkg dpkg-query; do
    path="$ROOT/usr/bin/$bin"
    [[ -f "$path" ]] && chmod o-x "$path"
done

# 2. Wrapper em /usr/local/bin/apt — intercepta antes do real (PATH prioriza local/bin)
install -d "$ROOT/usr/local/bin"
cat > "$ROOT/usr/local/bin/apt" << 'WRAPPER_EOF'
#!/usr/bin/env bash
if [[ $EUID -ne 0 ]]; then
    echo "Alinix: apt não está disponível para usuários comuns."
    echo "  Use alipack para instalar pacotes:"
    echo "    ali install <pacote>"
    echo "    ali search <termo>"
    echo "    ali help"
    exit 1
fi
# Root pode usar o apt real
exec /usr/bin/apt "$@"
WRAPPER_EOF
chmod 755 "$ROOT/usr/local/bin/apt"

# 3. Mesmo wrapper para apt-get
cat > "$ROOT/usr/local/bin/apt-get" << 'WRAPPER_EOF'
#!/usr/bin/env bash
if [[ $EUID -ne 0 ]]; then
    echo "Alinix: apt-get não está disponível para usuários comuns."
    echo "  Use: ali install <pacote>"
    exit 1
fi
exec /usr/bin/apt-get "$@"
WRAPPER_EOF
chmod 755 "$ROOT/usr/local/bin/apt-get"

# 4. Wrapper dpkg
cat > "$ROOT/usr/local/bin/dpkg" << 'WRAPPER_EOF'
#!/usr/bin/env bash
if [[ $EUID -ne 0 ]]; then
    echo "Alinix: dpkg não está disponível para usuários comuns."
    echo "  Use: ali install <pacote>.ali"
    echo "       ali compat <pacote>.deb"
    exit 1
fi
exec /usr/bin/dpkg "$@"
WRAPPER_EOF
chmod 755 "$ROOT/usr/local/bin/dpkg"

echo "apt/dpkg bloqueados para não-root. Usuários verão: 'Use alipack.'"
