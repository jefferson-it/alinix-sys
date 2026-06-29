# Alinix — Sistema Base

Este repositório contém o sistema base do **Alinix**: scripts de build da ISO, configurações de skel, assets e o `setup.sh` que monta o ambiente completo.

---

## O que é o Alinix?

O **Alinix** é um sistema operacional Linux de arquitetura livre, construído sobre **Ubuntu Noble 24.04** (debootstrap minbase), com desktop **GNOME Shell 46** customizado para oferecer uma experiência próxima ao macOS — mas com a liberdade do Linux.

**Princípios do projeto:**

- **Minimalismo**: nada além do necessário é instalado
- **Aparência coerente**: tema visual unificado (Dracula), botões à esquerda, painel macOS-like
- **Atalhos familiares**: Super como ⌘, atalhos macOS por padrão
- **FHS customizado**: caminhos amigáveis ao usuário (`/Users`, `/Exec`, `/Library`)
- **Apps próprios**: launcher, terminal, gerenciador de arquivos, configurações — tudo Alinix

**Kernel:** Alinix usa o [Kernel Lix](https://github.com/jefferson-it/kernel-lix), um fork do kernel Linux com patches voltados para uso em desktop e performance.

---

## Hierarquia do Sistema de Arquivos (FHS Alinix)

O Alinix implementa um FHS customizado sobre o FHS padrão do Linux. Os caminhos clássicos continuam funcionando via symlinks ou bind mounts — mas o usuário vê nomes mais amigáveis.

### Diretórios de usuário

| Alinix | Linux padrão | Descrição |
|--------|-------------|-----------|
| `/Users` | `/home` | Diretório dos usuários |
| `/Users/<nome>/Desktop` | `~/Desktop` | Área de trabalho |
| `/Users/<nome>/Documents` | `~/Documents` | Documentos |
| `/Users/<nome>/Downloads` | `~/Downloads` | Downloads |

### Sistema

| Alinix | Linux padrão | Descrição |
|--------|-------------|-----------|
| `/Exec` | `/usr/bin` + `/bin` | Executáveis do sistema |
| `/Library` | `/usr/lib` | Bibliotecas |
| `/Library/Frameworks` | `/usr/lib` | Frameworks |
| `/Var` | `/var` | Dados variáveis (logs, cache) |
| `/Etc` | `/etc` | Configurações do sistema |
| `/Volumes` | `/mnt` | Dispositivos montados |
| `/System` | `/usr` | Sistema base |
| `/Tmp` | `/tmp` | Arquivos temporários |

Os caminhos padrão do Linux (`/home`, `/usr/bin`, `/etc`, etc.) continuam funcionando normalmente para compatibilidade com pacotes existentes.

### Como funciona

O `alinix-init` (escrito em Rust) é executado antes do GDM3 e configura os bind mounts e symlinks necessários para que o FHS customizado funcione. Veja o app `alinix-init` para detalhes.

---

## Estrutura deste repositório

```
sys/
├── setup.sh                    # Script principal de build da ISO
├── transform-my-zorin.sh       # Transforma um Zorin OS existente em Alinix
├── skel/                       # Arquivos de home padrão (/etc/skel)
│   ├── .zshrc                  # ZSH configurado com Oh My Zsh
│   ├── alinix.zsh-theme        # Tema do shell estilo macOS
│   └── .config/                # Configs padrão (GTK, dconf)
└── assets/                     # Assets do sistema
    ├── AlinixLogo-Regular.otf  # Fonte com logo Alinix
    └── build-logo-font.py      # Script para rebuild da fonte
```

---

## Kernel Lix

O Alinix usa o [Kernel Lix](https://github.com/jefferson-it/kernel-lix) — um fork do kernel Linux com foco em:

- Performance em desktop (scheduler patches)
- Suporte aprimorado a hardware recente
- Patches de segurança adicionais

O `setup.sh` faz download e instala o kernel Lix durante o build da ISO.

---

## Como buildar a ISO

```bash
# Requer Ubuntu Noble 24.04 (ou chroot)
sudo bash setup.sh
```

O script executa as seguintes etapas:

1. **Debootstrap** — cria o sistema mínimo Ubuntu Noble
2. **Chroot** — entra no ambiente e instala pacotes
3. **GNOME** — instala GNOME Shell 46 sem gnome-core
4. **Apps** — clona e instala todos os apps do Alinix
5. **Skel** — configura home padrão, tema, ZSH
6. **Kernel Lix** — instala o kernel customizado
7. **ISO** — gera a imagem bootável com `mksquashfs` + GRUB

---

## Apps

Os apps do Alinix ficam em repositórios separados e são clonados automaticamente pelo `setup.sh`. Veja `architecture.md` para a lista completa e links.

---

# Alinix — Base System (English)

This repository contains the **Alinix** base system: ISO build scripts, skel configuration, assets and the `setup.sh` that assembles the complete environment.

## What is Alinix?

**Alinix** is a free-architecture Linux operating system, built on **Ubuntu Noble 24.04** (debootstrap minbase), with a **GNOME Shell 46** desktop customized to offer a macOS-like experience — but with Linux freedom.

**Project principles:**

- **Minimalism**: nothing beyond what's needed is installed
- **Coherent appearance**: unified visual theme (Dracula), left-side buttons, macOS-like panel
- **Familiar shortcuts**: Super as ⌘, macOS shortcuts by default
- **Custom FHS**: user-friendly paths (`/Users`, `/Exec`, `/Library`)
- **Own apps**: launcher, terminal, file manager, settings — all Alinix

**Kernel:** Alinix uses [Kernel Lix](https://github.com/jefferson-it/kernel-lix), a Linux kernel fork with patches aimed at desktop use and performance.

## File System Hierarchy (Alinix FHS)

Alinix implements a custom FHS on top of the standard Linux FHS. Classic paths keep working via symlinks or bind mounts — but the user sees friendlier names.

| Alinix | Standard Linux | Description |
|--------|---------------|-------------|
| `/Users` | `/home` | User directories |
| `/Exec` | `/usr/bin` + `/bin` | System executables |
| `/Library` | `/usr/lib` | Libraries |
| `/Volumes` | `/mnt` | Mounted devices |
| `/Etc` | `/etc` | System configuration |
| `/Var` | `/var` | Variable data |

## How to Build the ISO

```bash
# Requires Ubuntu Noble 24.04 (or chroot)
sudo bash setup.sh
```
