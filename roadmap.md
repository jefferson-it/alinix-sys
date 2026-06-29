# Roadmap do Alinix

## Milestone 1 — Fundação (em andamento)

Objetivo: ISO bootável com desktop funcional.

- [x] Debootstrap minbase Ubuntu Noble 24.04
- [x] GNOME Shell 46 sem metapacote gnome-core
- [x] ErasShell — painel macOS-like, Overview lock, atalhos
- [x] Tema Alinix Dracula (GTK3, GTK4, GNOME Shell)
- [x] JTerminal — terminal com atalhos Super (macOS)
- [x] Menu Global (GTK3 + GTK4)
- [x] Alinix Dock (Dash to Dock customizado)
- [x] Wobbly Windows
- [x] FHS customizado via alinix-init
- [x] Skel configurado (.zshrc, tema ZSH, GTK4)
- [x] build da ISO (`setup.sh`)
- [ ] Instalador gráfico (Alistaller) — funcional

## Milestone 2 — Aplicativos Essenciais

Objetivo: Substituir apps GNOME padrão por apps nativos Alinix.

- [ ] Alinix Settings (fork GCC completo com painéis Alinix)
- [ ] JExplorer — gerenciador de arquivos (Finder-like)
- [ ] QuickLook — visualizador rápido (Espaço no JExplorer)
- [ ] Alí — launcher (fork uLauncher) integrado ao ErasShell
- [ ] Alinix Init — testado e estável em produção

## Milestone 3 — Experiência Polida

Objetivo: Experiência sem arestas, indistinguível de um produto comercial.

- [ ] Launchpad animado no ErasShell
- [ ] Notch virtual (painel superior com entalhe visual)
- [ ] Animações de abertura/fechamento de janela
- [ ] Gestos de touchpad (Touchégg integrado)
- [ ] ErasShell: indicador de rede cabeada
- [ ] Wallpaper padrão Alinix
- [ ] Som de inicialização
- [ ] Fonte do sistema (AlinixLogo integrado)
- [ ] OSD de volume/brilho customizado

## Milestone 4 — Ecossistema de Pacotes

Objetivo: Sistema de pacotes próprio funcionando.

- [ ] Alipack — operações reais (install, remove, update, upgrade)
- [ ] Repositório ALI público
- [ ] pkg-compat — suporte a .deb, .rpm, .AppImage, .snap, .flatpak
- [ ] Alipack integrado ao Alistaller (pós-install)
- [ ] AliStore — loja de aplicativos gráfica

## Milestone 5 — Kernel Lix

Objetivo: Kernel próprio estável e mantido.

- [ ] Kernel Lix — patches de performance desktop
- [ ] Integrado ao build da ISO
- [ ] Driver Wifi/BT out-of-the-box (realtek, mediatek)
- [ ] Suporte a hardware Apple (M1 via Asahi patches)

## Milestone 6 — Multi-arquitetura e Hardware

- [ ] ISO arm64 (Raspberry Pi 4/5, Apple M-series)
- [ ] Alinix para tablets (touch-first)
- [ ] Alinix Server (sem desktop, só CLI + Alipack)

---

# Alinix Roadmap (English)

## Milestone 1 — Foundation (in progress)

Goal: Bootable ISO with functional desktop.

- [x] Debootstrap minbase Ubuntu Noble 24.04
- [x] GNOME Shell 46 without gnome-core metapackage
- [x] ErasShell — macOS-like panel, Overview lock, shortcuts
- [x] Alinix Dracula theme (GTK3, GTK4, GNOME Shell)
- [x] JTerminal — terminal with Super shortcuts (macOS)
- [x] Global Menu (GTK3 + GTK4)
- [x] Alinix Dock (customized Dash to Dock)
- [x] Wobbly Windows
- [x] Custom FHS via alinix-init
- [x] Skel configured (.zshrc, ZSH theme, GTK4)
- [x] ISO build (`setup.sh`)
- [ ] Graphical installer (Alistaller) — functional

## Milestone 2 — Essential Applications

Goal: Replace default GNOME apps with native Alinix apps.

- [ ] Alinix Settings (full GCC fork with Alinix panels)
- [ ] JExplorer — file manager (Finder-like)
- [ ] QuickLook — quick viewer (Space in JExplorer)
- [ ] Alí — launcher (uLauncher fork) integrated with ErasShell
- [ ] Alinix Init — tested and stable in production

## Milestone 3 — Polished Experience

Goal: Seamless experience, indistinguishable from a commercial product.

- [ ] Animated Launchpad in ErasShell
- [ ] Virtual notch (panel with visual notch)
- [ ] Window open/close animations
- [ ] Touchpad gestures (Touchégg integrated)
- [ ] ErasShell: wired network indicator
- [ ] Default Alinix wallpaper
- [ ] Startup sound
- [ ] System font (AlinixLogo integrated)
- [ ] Custom volume/brightness OSD

## Milestone 4 — Package Ecosystem

Goal: Own package system working.

- [ ] Alipack — real operations (install, remove, update, upgrade)
- [ ] Public ALI repository
- [ ] pkg-compat — support for .deb, .rpm, .AppImage, .snap, .flatpak
- [ ] Alipack integrated in Alistaller (post-install)
- [ ] AliStore — graphical app store

## Milestone 5 — Kernel Lix

Goal: Own stable and maintained kernel.

- [ ] Kernel Lix — desktop performance patches
- [ ] Integrated in ISO build
- [ ] Wifi/BT driver out-of-the-box (realtek, mediatek)
- [ ] Apple hardware support (M1 via Asahi patches)

## Milestone 6 — Multi-arch and Hardware

- [ ] arm64 ISO (Raspberry Pi 4/5, Apple M-series)
- [ ] Alinix for tablets (touch-first)
- [ ] Alinix Server (no desktop, CLI + Alipack only)
