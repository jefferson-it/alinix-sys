#!/usr/bin/env bash
# Alinix — Script de instalação e configuração da camada visual do GNOME
set -euo pipefail

ALINIX_ROOT="${ALINIX_ROOT:-}"
if [ -z "$ALINIX_ROOT" ]; then
  echo "Aviso: ALINIX_ROOT não definido, instalando no sistema local ativo."
  R=""
else
  R="$ALINIX_ROOT"
  echo "Instalando a camada visual no chroot: $R"
fi

SELF="$(cd "$(dirname "$0")" && pwd)"

# 1. Configurar Gestos (Touchégg)
echo ">> Configurando gestos de touchpad (Touchégg)..."
install -d "$R/etc/touchegg"
[ -f "$SELF/touchegg.conf" ] && cp "$SELF/touchegg.conf" "$R/etc/touchegg/touchegg.conf"

# 2. Copiar e Compilar Esquemas GSettings do GNOME
echo ">> Injetando esquemas GSettings do Alinix..."
install -d "$R/usr/share/glib-2.0/schemas"
[ -f "$SELF/99_alinix_desktop.gschema.override" ] && \
  cp "$SELF/99_alinix_desktop.gschema.override" "$R/usr/share/glib-2.0/schemas/99_alinix_desktop.gschema.override"

# 3. Variáveis de ambiente para Menu Global
echo ">> Configurando variáveis de ambiente para Menu Global..."
install -d "$R/etc/profile.d"
cat > "$R/etc/profile.d/alinix-menu.sh" << 'EOF'
export UBUNTU_MENUPROXY=1
EOF
chmod +x "$R/etc/profile.d/alinix-menu.sh"

# 4. Criar estrutura de temas e extensões
echo ">> Criando diretórios para temas e extensões..."
install -d "$R/usr/share/themes"
install -d "$R/usr/share/gnome-shell/extensions"
install -d "$R/usr/share/glib-2.0/schemas"

# ── Tema alinix-dracula ──────────────────────────────────────────────────────
echo ">> Copiando tema alinix-dracula..."
THEME_SRC="$SELF/../../apps/themes/alinix-dracula"
if [ -d "$THEME_SRC" ]; then
  rm -rf "$R/usr/share/themes/alinix-dracula"
  cp -r "$THEME_SRC" "$R/usr/share/themes/alinix-dracula"

  # GTK4: apps nativos lêem ~/.config/gtk-4.0/gtk.css — copiado no skel
  # para que todo usuário novo já receba o tema automaticamente
  mkdir -p "$R/etc/skel/.config/gtk-4.0"
  cp "$THEME_SRC/gtk-4.0/gtk.css"      "$R/etc/skel/.config/gtk-4.0/gtk.css"
  cp "$THEME_SRC/gtk-4.0/gtk-dark.css" "$R/etc/skel/.config/gtk-4.0/gtk-dark.css" 2>/dev/null || true
  [ -d "$THEME_SRC/gtk-4.0/assets" ] && \
    cp -r "$THEME_SRC/gtk-4.0/assets" "$R/etc/skel/.config/gtk-4.0/assets" || true

  # Flatpak lê ~/.themes/<nome>/gtk-4.0/ com --filesystem=~/.themes
  mkdir -p "$R/etc/skel/.themes"
  cp -r "$THEME_SRC" "$R/etc/skel/.themes/alinix-dracula"

  echo "   Tema alinix-dracula copiado (/usr/share/themes + skel GTK4 + skel Flatpak)"
else
  echo "   AVISO: tema alinix-dracula não encontrado em $THEME_SRC"
fi

# Symlink /Library/Themes se o diretório existir
[ -d "$R/Library" ] && ln -sfn /usr/share/themes "$R/Library/Themes" || true

# ── Extensão menu-global@alinix.osx (GTK3 / legado) ────────────────────────
echo ">> Copiando extensão menu-global@alinix.osx..."
EXT_SRC="$SELF/../../apps/menu-global/menu-global@alinix.osx"
if [ -d "$EXT_SRC" ]; then
  EXT_DEST="$R/usr/share/gnome-shell/extensions/menu-global@alinix.osx"
  rm -rf "$EXT_DEST"
  cp -r "$EXT_SRC" "$EXT_DEST"
  if [ -f "$EXT_SRC/schemas/org.gnome.shell.extensions.menu-global.gschema.xml" ]; then
    cp "$EXT_SRC/schemas/org.gnome.shell.extensions.menu-global.gschema.xml" \
       "$R/usr/share/glib-2.0/schemas/"
    [ -d "$EXT_DEST/schemas" ] && \
      glib-compile-schemas "$EXT_DEST/schemas/" 2>/dev/null || true
  fi
  echo "   menu-global@alinix.osx instalado."
fi

# ── Extensão menu-global-gtk4@alinix.osx (GTK4 / Libadwaita) ───────────────
echo ">> Copiando extensão menu-global-gtk4@alinix.osx..."
EXT4_SRC="$SELF/../../apps/menu-global-gtk4/menu-global-gtk4@alinix.osx"
if [ -d "$EXT4_SRC" ]; then
  EXT4_DEST="$R/usr/share/gnome-shell/extensions/menu-global-gtk4@alinix.osx"
  rm -rf "$EXT4_DEST"
  cp -r "$EXT4_SRC" "$EXT4_DEST"
  if [ -d "$EXT4_SRC/schemas" ]; then
    for schema_xml in "$EXT4_SRC/schemas/"*.xml; do
      [ -f "$schema_xml" ] && cp "$schema_xml" "$R/usr/share/glib-2.0/schemas/" || true
    done
    glib-compile-schemas "$EXT4_DEST/schemas/" 2>/dev/null || true
  fi
  echo "   menu-global-gtk4@alinix.osx instalado."
else
  echo "   AVISO: menu-global-gtk4@alinix.osx não encontrado em $EXT4_SRC"
fi

# ── Extensão wobbly-windows@weinberg.org ────────────────────────────────────
echo ">> Copiando extensão wobbly-windows@weinberg.org..."
WOBBLY_SRC="$SELF/../../apps/wobbly-windows/wobbly-windows@weinberg.org"
if [ -d "$WOBBLY_SRC" ]; then
  WOBBLY_DEST="$R/usr/share/gnome-shell/extensions/wobbly-windows@weinberg.org"
  rm -rf "$WOBBLY_DEST"
  cp -r "$WOBBLY_SRC" "$WOBBLY_DEST"
  if [ -f "$WOBBLY_SRC/schemas/org.gnome.shell.extensions.wobbly-windows.gschema.xml" ]; then
    cp "$WOBBLY_SRC/schemas/org.gnome.shell.extensions.wobbly-windows.gschema.xml" \
       "$R/usr/share/glib-2.0/schemas/"
    [ -d "$WOBBLY_DEST/schemas" ] && \
      glib-compile-schemas "$WOBBLY_DEST/schemas/" 2>/dev/null || true
  fi
  echo "   wobbly-windows@weinberg.org instalado."
fi

# 5. Instalar o aplicativo de Configurações nativo (alinix-settings)
echo ">> Instalando o aplicativo de Configurações Alinix (alinix-settings)..."
install -d "$R/usr/bin"
[ -f "$SELF/../../apps/desktop/config-app/alinix-settings.py" ] && \
  install -Dm755 "$SELF/../../apps/desktop/config-app/alinix-settings.py" "$R/usr/bin/alinix-settings"

install -d "$R/usr/share/applications"
[ -f "$SELF/../../apps/desktop/config-app/alinix-settings.desktop" ] && \
  cp "$SELF/../../apps/desktop/config-app/alinix-settings.desktop" "$R/usr/share/applications/alinix-settings.desktop"

LOGO="$SELF/../assets/logo.svg"
if [ -f "$LOGO" ]; then
  install -d "$R/usr/share/pixmaps"
  cp "$LOGO" "$R/usr/share/pixmaps/alinix-settings.svg"
  cp "$LOGO" "$R/usr/share/pixmaps/alinix-logo.svg"
  install -d "$R/usr/share/icons/hicolor/scalable/apps"
  ln -sfn /usr/share/pixmaps/alinix-settings.svg "$R/usr/share/icons/hicolor/scalable/apps/alinix-settings.svg"
  ln -sfn /usr/share/pixmaps/alinix-logo.svg     "$R/usr/share/icons/hicolor/scalable/apps/alinix-logo.svg"
fi

# 6. Compilar todos os schemas (inclui override + extensões)
if command -v glib-compile-schemas >/dev/null 2>&1; then
  echo ">> Compilando esquemas GSettings (global)..."
  glib-compile-schemas "$R/usr/share/glib-2.0/schemas/"
else
  echo "Aviso: glib-compile-schemas não encontrado. Será compilado no chroot."
fi

echo ">> Instalação da camada visual do desktop concluída."
