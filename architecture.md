# Arquitetura do Alinix

## Visão geral

```
┌─────────────────────────────────────────────────────┐
│                    ISO Alinix                        │
│  ┌──────────────────────────────────────────────┐   │
│  │              GNOME Shell 46                  │   │
│  │  ┌─────────────┐  ┌──────────────────────┐  │   │
│  │  │  ErasShell  │  │   menu-global (GTK3) │  │   │
│  │  │  extension  │  │   menu-global-gtk4   │  │   │
│  │  └─────────────┘  └──────────────────────┘  │   │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐  │   │
│  │  │alinix-   │  │ wobbly-  │  │alinix-    │  │   │
│  │  │dock      │  │ windows  │  │ settings  │  │   │
│  │  └──────────┘  └──────────┘  └───────────┘  │   │
│  └──────────────────────────────────────────────┘   │
│  ┌────────────┐  ┌───────────┐  ┌──────────────┐   │
│  │ JTerminal  │  │ JExplorer │  │     Alí      │   │
│  │ (GTK4+VTE) │  │ (Finder)  │  │  (launcher)  │   │
│  └────────────┘  └───────────┘  └──────────────┘   │
│  ┌──────────────────────────────────────────────┐   │
│  │        Ubuntu Noble 24.04 (base)             │   │
│  │  apt · systemd · GDM3 · PipeWire · NetworkM  │   │
│  └──────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────┐   │
│  │              Kernel Lix                      │   │
│  │  github.com/jefferson-it/kernel-lix          │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

---

## Camadas

### 1. Kernel Lix

Fork do kernel Linux com patches para desktop:
- Scheduler patches (latência reduzida)
- Driver patches (wifi/BT)
- Repositório: https://github.com/jefferson-it/kernel-lix

### 2. Base do Sistema (Ubuntu Noble)

Instalado via `debootstrap --variant=minbase`:
- `systemd` — init, udev, logind
- `GDM3` — gerenciador de login
- `PipeWire` — áudio (substitui PulseAudio)
- `NetworkManager` — rede (wi-fi + ethernet)
- **Sem** `gnome-core` — GNOME Shell instalado à la carte

### 3. GNOME Shell 46

Componentes instalados diretamente:
- `gnome-shell` — compositor + shell
- `mutter` — window manager Wayland/X11
- `gdm3` — login
- `gnome-session` — sessão
- Sem: `gnome-software`, `gnome-control-center` (substituído pelo Alinix Settings)

### 4. Extensões GNOME Shell

| Extensão | Função |
|----------|--------|
| `erasshell@alinix` | Tudo — painel, Launchpad, Alí, overview lock |
| `menu-global@alinix.osx` | Barra de menu do app no painel (GTK3/Qt) |
| `menu-global-gtk4@alinix.osx` | Barra de menu do app no painel (GTK4) |
| `alinix-dock@alinix` | Dock inferior (Dash to Dock fork) |
| `wobbly-windows@weinberg.org` | Efeito wobbly nas janelas |
| `user-theme@gnome-shell-extensions.gcampax.github.com` | Tema do shell |

### 5. Apps Alinix

| App | Tecnologia | Função |
|-----|-----------|--------|
| `alinix-settings` | C / GCC fork | Configurações do sistema |
| `jterminal` | Python + GTK4 + VTE | Terminal |
| `jexplorer` | Python + GTK4 | Gerenciador de arquivos |
| `ali` | Python (uLauncher fork) | Launcher |
| `alistaller` | Python + GTK4 | Instalador gráfico |
| `quicklook` | Python + GTK4 | Visualizador rápido |
| `alipack` | Rust | Gerenciador de pacotes |
| `pkg-compat` | Bash/Python | Compatibilidade .deb/.rpm/etc |
| `alinix-init` | Rust | Init customizado (FHS) |

### 6. Temas

| Componente | Tema |
|-----------|------|
| GTK 3 | alinix-dracula |
| GTK 4 | alinix-dracula (`~/.config/gtk-4.0/gtk.css`) |
| GNOME Shell | alinix-dracula (via user-theme) |
| Ícones | Papirus-Dark |
| Cursor | Adwaita |
| Fonte | Inter + AlinixLogo |

---

## Repositórios

O repositório `sys/` (este) é o ponto de entrada do projeto. Cada app tem seu próprio repositório Git e é clonado pelo `setup.sh` durante o build.

| App | Repositório (a preencher) |
|-----|--------------------------|
| `sys` | *(este repo)* |
| `erasshell` | a ser definido |
| `alinix-settings` | a ser definido |
| `jterminal` | a ser definido |
| `jexplorer` | a ser definido |
| `ali` | a ser definido |
| `alinix-dock` | a ser definido |
| `alinix-init` | a ser definido |
| `alipack` | a ser definido |
| `alistaller` | a ser definido |
| `themes` | a ser definido |
| `menu-global` | a ser definido |
| `menu-global-gtk4` | a ser definido |
| `wobbly-windows` | a ser definido |
| `quicklook` | a ser definido |
| `pkg-compat` | a ser definido |

---

## Fluxo de Build

```
setup.sh
  │
  ├── debootstrap → /build/chroot/
  │
  ├── chroot:
  │   ├── apt install gnome-shell mutter gdm3 ...
  │   ├── git clone apps → /build/chroot/tmp/apps/
  │   │   └── (cada app) make install / bash install.sh
  │   ├── glib-compile-schemas (extensões)
  │   ├── dconf load (configurações padrão)
  │   └── cp skel → /etc/skel/
  │
  ├── mksquashfs → filesystem.squashfs
  │
  └── grub-mkrescue → alinix.iso
```

---

# Alinix Architecture (English)

## Layers

1. **Kernel Lix** — Linux kernel fork for desktop performance
2. **Ubuntu Noble base** — debootstrap minbase, no gnome-core
3. **GNOME Shell 46** — compositor + WM, installed à la carte
4. **GNOME Shell Extensions** — ErasShell, Global Menu, Dock, Wobbly
5. **Alinix Apps** — Settings, Terminal, File Manager, Launcher, Installer, Package Manager
6. **Alinix Theme** — Dracula-based, GTK3/4/Shell, unified visual

## Repositories

Each app lives in its own Git repository and is cloned by `setup.sh` during the ISO build. See the table above for repo links (to be filled in after GitHub push).

## Build Flow

`setup.sh` orchestrates: debootstrap → apt install → git clone apps → install apps → compile schemas → copy skel → mksquashfs → ISO.
