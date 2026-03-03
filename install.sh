#!/bin/bash

set -e

VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
ROJO='\033[0;31m'
NC='\033[0m'

LOG_FILE="/var/log/fedora-postinstall.log"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

banner() {
    clear
    echo -e "${AZUL}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${AZUL}║${NC}     Fedora PostInstall - Configuración Automática        ${AZUL}║${NC}"
    echo -e "${AZUL}║${NC}                                                          ${AZUL}║${NC}"
    echo -e "${AZUL}║${NC}  Transforma tu Fedora en estación de trabajo           ${AZUL}║${NC}"
    echo -e "${AZUL}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &> /dev/null; then
            log "${ROJO}Error: sudo no está instalado${NC}"
            exit 1
        fi
    fi
}

check_fedora() {
    if [[ ! -f /etc/fedora-release ]]; then
        log "${ROJO}Error: Este script está diseñado solo para Fedora${NC}"
        exit 1
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local yn
    
    if [[ "$default" == "y" ]]; then
        while true; do
            read -p "$prompt [Y/n]: " yn
            case $yn in
                [Yy]*|"") return 0 ;;
                [Nn]*) return 1 ;;
                *) echo "Responde y o n" ;;
            esac
        done
    else
        while true; do
            read -p "$prompt [y/N]: " yn
            case $yn in
                [Yy]*) return 0 ;;
                [Nn]*|"") return 1 ;;
                *) echo "Responde y o n" ;;
            esac
        done
    fi
}

run_cmd() {
    local cmd="$1"
    local desc="$2"
    log "${AMARILLO}>> $desc${NC}"
    log "   Comando: $cmd"
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log "${VERDE}✓ Completado${NC}"
        return 0
    else
        log "${ROJO}✗ Error en: $desc${NC}"
        return 1
    fi
}

optimize_dnf() {
    log ""
    log "${AZUL}=== Optimizando DNF ===${NC}"
    
    local dnf_conf="/etc/dnf/dnf.conf"
    local backup="$dnf_conf.bak.$(date +%Y%m%d%H%M%S)"
    
    if [[ -f "$dnf_conf" ]]; then
        sudo cp "$dnf_conf" "$backup"
        log "Backup creado: $backup"
    fi
    
    cat | sudo tee "$dnf_conf" > /dev/null << 'EOF'
[main]
fastestmirror=True
max_parallel_downloads=20
gpgcheck=True
installonly_limit=2
clean_requirements_on_remove=True
best=False
skip_if_unavailable=True
keepcache=False
EOF
    
    log "${VERDE}✓ DNF optimizado${NC}"
}

add_repos() {
    log ""
    log "${AZUL}=== Agregando repositorios RPMFusion ===${NC}"
    
    run_cmd "sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm" "RPMFusion Free"
    run_cmd "sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$(rpm -E %fedora).noarch.rpm" "RPMFusion Non-Free"
    run_cmd "sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted" "RPMFusion Tainted"
    run_cmd "sudo dnf makecache" "Actualizar cache"
    
    log "${VERDE}✓ Repositorios agregados${NC}"
}

update_firmware() {
    log ""
    log "${AZUL}=== Actualizando firmware via LVFS ===${NC}"
    
    run_cmd "sudo fwupdmgr refresh --force" "Refrescar LVFS" || true
    run_cmd "sudo fwupdmgr get-devices" "Listar dispositivos" || true
    run_cmd "sudo fwupdmgr get-updates" "Buscar actualizaciones" || true
    run_cmd "sudo fwupdmgr update" "Actualizar firmware" || true
    
    log "${AMARILLO}⚠ Reinicia el sistema después de actualizar firmware${NC}"
}

install_nvidia() {
    log ""
    log "${AZUL}=== Instalando drivers NVIDIA ===${NC}"
    
    run_cmd "sudo dnf upgrade --refresh" "Actualizar sistema"
    run_cmd "sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda" "Drivers NVIDIA"
    
    log "${AMARILLO}⚠ Reinicia el sistema después de instalar drivers NVIDIA${NC}"
}

install_multimedia() {
    log ""
    log "${AZUL}=== Configurando Multimedia ===${NC}"
    
    run_cmd "sudo dnf swap ffmpeg-free ffmpeg --allowerasing" "FFmpeg completo"
    run_cmd "sudo dnf install -y @multimedia --setopt='install_weak_deps=False' --exclude=PackageKit-gstreamer-plugin" "Grupo Multimedia"
    run_cmd "sudo dnf group install -y sound-and-video" "Sound and Video"
    run_cmd "sudo dnf install -y libdvdcss" "LibDVDCSS"
    run_cmd "sudo dnf --repo=rpmfusion-nonfree-tainted install -y '*-firmware'" "Firmwares adicionales"
    run_cmd "sudo dnf install -y ffmpeg-libs libva libva-utils" "Librerías video"
    
    log "${VERDE}✓ Multimedia configurado${NC}"
}

install_apps() {
    log ""
    log "${AZUL}=== Instalando aplicaciones ===${NC}"
    
    run_cmd "sudo dnf install -y vlc gimp obs-studio shotcut" "Apps multimedia"
    
    log "${VERDE}✓ Aplicaciones instaladas${NC}"
}

install_fonts() {
    log ""
    log "${AZUL}=== Instalando fuentes Windows ===${NC}"
    
    run_cmd "sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig" "Dependencias fuentes"
    run_cmd "sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm" "Microsoft Core Fonts"
    
    log "${VERDE}✓ Fuentes instaladas${NC}"
}

install_browsers() {
    log ""
    log "${AZUL}=== Instalando navegadores ===${NC}"
    
    run_cmd "sudo dnf install -y dnf-plugins-core fedora-workstation-repositories" "Plugins DNF"
    run_cmd "sudo dnf config-manager setopt google-chrome.enabled=1" "Habilitar Chrome"
    run_cmd "sudo dnf install -y google-chrome-stable" "Chrome"
    
    run_cmd "sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo" "Repo Brave"
    run_cmd "sudo dnf install -y brave-browser" "Brave"
    
    log "${VERDE}✓ Navegadores instalados${NC}"
}

install_gaming() {
    log ""
    log "${AZUL}=== Configurando Gaming ===${NC}"
    
    run_cmd "sudo dnf install -y steam" "Steam"
    run_cmd "sudo dnf install -y mangohud goverlay" "MangoHud"
    
    log "${AMARILLO}⚠ GameMode requiere compilación manual. Ver docs/gaming.md${NC}"
    
    log "${VERDE}✓ Gaming configurado${NC}"
}

install_dev_tools() {
    log ""
    log "${AZUL}=== Configurando entorno de desarrollo ===${NC}"
    
    run_cmd "sudo dnf group install -y development-tools" "Development Tools"
    run_cmd "sudo dnf install -y gcc gcc-c++ make clang patch glibc-devel openssl-devel zlib-devel pkg-config readline-devel libffi-devel libyaml-devel gdbm-devel ncurses-devel" "Librerías desarrollo"
    
    log "${VERDE}✓ Herramientas de desarrollo instaladas${NC}"
}

install_dev_shell() {
    log ""
    log "${AZUL}=== Configurando shell Zsh ===${NC}"
    
    run_cmd "sudo dnf install -y zsh" "Zsh"
    
    if ask_yes_no "¿Instalar Oh My Zsh?"; then
        run_cmd "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"" "Oh My Zsh" || true
    fi
    
    if ask_yes_no "¿Instalar tema Powerlevel10k?"; then
        run_cmd "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" "Powerlevel10k"
    fi
    
    if ask_yes_no "¿Instalar plugin zsh-autosuggestions?"; then
        run_cmd "git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-\$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" "zsh-autosuggestions"
    fi
    
    log "${VERDE}✓ Shell configurado${NC}"
}

install_dev_languages() {
    log ""
    log "${AZUL}=== Configurando lenguajes de programación ===${NC}"
    
    if ask_yes_no "¿Instalar Rust?"; then
        run_cmd "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" "Rust" || true
    fi
    
    if ask_yes_no "¿Instalar Go?"; then
        log "${AMARILLO}⚠ Go debe descargarse manualmente desde golang.org/dl${NC}"
    fi
    
    if ask_yes_no "¿Instalar NVM (Node.js)?"; then
        run_cmd "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash" "NVM" || true
    fi
    
    if ask_yes_no "¿Instalar UV (Python)?"; then
        run_cmd "curl -LsSf https://astral.sh/uv/install.sh | sh" "UV" || true
    fi
    
    log "${VERDE}✓ Lenguajes configurados${NC}"
}

install_dev_docker() {
    log ""
    log "${AZUL}=== Configurando Docker ===${NC}"
    
    run_cmd "sudo dnf install -y dnf-plugins-core" "DNF plugins"
    run_cmd "sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo" "Docker repo"
    run_cmd "sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Docker"
    run_cmd "sudo systemctl enable --now docker" "Iniciar Docker"
    run_cmd "sudo groupadd docker 2>/dev/null || true" "Grupo docker"
    run_cmd "sudo usermod -aG docker $USER" "Agregar usuario a docker"
    
    log "${AMARILLO}⚠ Cierra sesión y vuelve a entrar para usar Docker sin sudo${NC}"
    log "${VERDE}✓ Docker configurado${NC}"
}

install_dev_ide() {
    log ""
    log "${AZUL}=== Configurando IDEs ===${NC}"
    
    run_cmd "sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc" "Key VS Code"
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
    run_cmd "sudo dnf install -y code" "VS Code"
    
    if ask_yes_no "¿Instalar DBeaver (Flatpak)?"; then
        if command -v flatpak &> /dev/null; then
            run_cmd "flatpak install -y flathub io.dbeaver.DBeaverCommunity" "DBeaver"
        else
            log "${AMARILLO}⚠ Flatpak no está instalado. Instala Flatpak primero.${NC}"
        fi
    fi
    
    log "${VERDE}✓ IDEs configurados${NC}"
}

main_menu() {
    local exit_menu=0
    
    while [[ $exit_menu -eq 0 ]]; do
        banner
        echo -e "${VERDE}Selecciona qué deseas instalar:${NC}"
        echo ""
        echo -e "  ${AZUL}[1]${NC} Optimizar DNF"
        echo -e "  ${AZUL}[2]${NC} Agregar repositorios (RPMFusion)"
        echo -e "  ${AZUL}[3]${NC} Actualizar firmware (LVFS)"
        echo -e "  ${AZUL}[4]${NC} Instalar drivers NVIDIA"
        echo -e "  ${AZUL}[5]${NC} Multimedia (codecs + apps)"
        echo -e "  ${AZUL}[6]${NC} Fuentes Windows"
        echo -e "  ${AZUL}[7]${NC} Navegadores (Chrome + Brave)"
        echo -e "  ${AZUL}[8]${NC} Gaming (Steam + MangoHud)"
        echo -e "  ${AZUL}[9]${NC} Desarrollo (herramientas base)"
        echo -e "  ${AZUL}[10]${NC} Desarrollo (shell Zsh)"
        echo -e "  ${AZUL}[11]${NC} Desarrollo (lenguajes)"
        echo -e "  ${AZUL}[12]${NC} Desarrollo (Docker)"
        echo -e "  ${AZUL}[13]${NC} Desarrollo (IDEs)"
        echo -e "  ${AZUL}[14]${NC} ${AMARILLO}INSTALAR TODO${NC}"
        echo ""
        echo -e "  ${ROJO}[0]${NC} Salir"
        echo ""
        
        read -p "Opción: " option
        
        case $option in
            1)  optimize_dnf ;;
            2)  add_repos ;;
            3)  update_firmware ;;
            4)  install_nvidia ;;
            5)  install_multimedia; install_apps ;;
            6)  install_fonts ;;
            7)  install_browsers ;;
            8)  install_gaming ;;
            9)  install_dev_tools ;;
            10) install_dev_shell ;;
            11) install_dev_languages ;;
            12) install_dev_docker ;;
            13) install_dev_ide ;;
            14)
                log "${AMARILLO}=== INSTALANDO TODO ===${NC}"
                optimize_dnf
                add_repos
                update_firmware
                install_nvidia
                install_multimedia
                install_apps
                install_fonts
                install_browsers
                install_gaming
                install_dev_tools
                install_dev_shell
                install_dev_languages
                install_dev_docker
                install_dev_ide
                log "${VERDE}=== INSTALACIÓN COMPLETA ===${NC}"
                ;;
            0)
                exit_menu=1
                log "¡Hasta luego!"
                ;;
            *)
                echo "Opción inválida"
                sleep 1
                ;;
        esac
        
        if [[ $exit_menu -eq 0 && $option -ne 14 ]]; then
            echo ""
            read -p "Presiona Enter para continuar..."
        fi
    done
}

main() {
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/fedora-postinstall.log"
    
    check_fedora
    check_root
    
    banner
    echo -e "Bienvenido a Fedora PostInstall"
    echo -e "Log: $LOG_FILE"
    echo ""
    
    if ask_yes_no "¿Ejecutar en modo interactivo?" "y"; then
        main_menu
    else
        echo "Ejecuta con -h para ver opciones"
    fi
}

main "$@"
