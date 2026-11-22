#!/usr/bin/env bash
#
# Fedora PostInstall
# ------------------
# Deja una instalación recién hecha de Fedora Workstation lista para
# desarrollo, edición de foto/video y gaming, sin hacer preguntas.
#
#   curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash
#
# Se puede volver a ejecutar cuantas veces quieras: cada paso detecta lo que ya
# está hecho y solo instala o actualiza lo que falta.
#
# Todo vive dentro de funciones y recién se ejecuta en la última línea
# (main "$@"). Con `curl | bash` eso garantiza que bash leyó el archivo completo
# antes de hacer nada: una descarga cortada no deja una instalación a medias.

set -uo pipefail

readonly REPO_RAW="https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh"
readonly MIN_FEDORA=43            # Últimas 3 versiones: 43, 44 y 45.
readonly MAX_TESTED_FEDORA=45
readonly NVM_VERSION="v0.40.4"
readonly MSFONTS_RPM="https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm"
readonly PPTVIEWER_URL="https://archive.org/download/PowerPointViewer_201801/PowerPointViewer.exe"
readonly PPTVIEWER_SHA256="249473568eba7a1e4f95498acba594e0f42e6581add4dead70c1dfb908a09423"

LOG_FILE="$HOME/fedora-postinstall-$(date +%Y%m%d-%H%M%S).log"
ARCH="$(uname -m)"
USER_NAME="$(id -un)"
FEDORA_VERSION=""
WORK_DIR=""
BG_PIDS=()
GPU_INFO=""
SKIP_REASON=""
LAST_ERROR=""
ONLY=""
SKIP=""
NOTES=()
OK=()
FAILED=()
FAILED_IDS=()
SKIPPED=()

# id|descripción — se ejecutan en este orden. La función de cada paso es step_<id>.
STEPS=(
  "dnf|Optimizar DNF y herramientas base"
  "snapshots|Snapshots automáticos antes de cada dnf (Btrfs)"
  "upgrade|Actualizar el sistema"
  "limits|Límites de inotify para editores y agentes"
  "repos|Repositorios RPM Fusion y Flathub"
  "firmware|Firmware (LVFS)"
  "nvidia|Drivers NVIDIA"
  "multimedia|Codecs multimedia"
  "hwaccel|Aceleración de video por hardware"
  "fonts|Fuentes de Microsoft"
  "compression|Herramientas de compresión"
  "latex|LaTeX completo"
  "chrome|Google Chrome"
  "brave|Brave"
  "apps|VLC, GIMP, OBS Studio (+ captura de juegos), Shotcut"
  "office|ONLYOFFICE (Flatpak)"
  "gaming|Steam, Gamescope, GameMode, MangoHud y ProtonUp-Qt"
  "ntsync|NTSYNC para juegos (Wine/GE-Proton)"
  "protonge|GE-Proton (última versión)"
  "devtools|Herramientas de desarrollo"
  "cli|CLI para agentes (gh, ripgrep, fd, fzf, jq, delta, lazygit, direnv, distrobox)"
  "zsh|Zsh + Oh My Zsh + Powerlevel10k"
  "ghostty|Terminal Ghostty"
  "rust|Rust"
  "go|Go"
  "node|Node.js LTS (NVM)"
  "uv|uv (Python)"
  "docker|Docker"
  "zed|Zed"
  "cursor|Cursor"
  "dbeaver|DBeaver (Flatpak)"
  "claude|Claude Code"
  "opencode|OpenCode"
  "herdr|Herdr (multiplexor para agentes de IA)"
  "obsidian|Obsidian (Flatpak)"
  "env|Variables de entorno (PATH, Go, NVM)"
)

if [[ -t 1 ]]; then
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
  C_GREEN=$'\e[32m' C_RED=$'\e[31m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_RED="" C_YELLOW="" C_BLUE=""
fi

# ─── Utilidades ───────────────────────────────────────────────────────────────

say()  { printf '%s\n' "$*"; }
die()  { printf '%sError:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
log()  { printf '%s\n' "$*" >>"$LOG_FILE"; }
skip() { SKIP_REASON="$1"; return 99; }

# Agrega una tarea pendiente al resumen final (sin duplicados).
note() {
  local n
  for n in "${NOTES[@]}"; do [[ $n == "$1" ]] && return 0; done
  NOTES+=("$1")
}

# Ejecuta un comando sin acceso al teclado y con su salida solo en el log.
# Si algo intentara preguntar, falla en vez de quedarse colgado esperando.
run() {
  log "\$ $*"
  "$@" </dev/null >>"$LOG_FILE" 2>&1
}

# Descarga una URL a un archivo temporal e imprime su ruta. Los instaladores
# oficiales (rustup, uv, nvm…) se bajan primero y se ejecutan después, en vez
# de `curl | sh`, para detectar una descarga fallida antes de ejecutar nada.
download() {
  local file
  file=$(mktemp -p "$WORK_DIR") || return 1
  log "\$ curl $1"
  curl -fsSL --retry 3 --connect-timeout 20 -o "$file" "$1" >>"$LOG_FILE" 2>&1 || {
    LAST_ERROR="no se pudo descargar $1"
    return 1
  }
  printf '%s' "$file"
}

# Escribe un archivo de sistema (p. ej. un .repo) con sudo.
write_root_file() {
  log "\$ escribir $1"
  if ! sudo mkdir -p "$(dirname "$1")" 2>>"$LOG_FILE" ||
    ! printf '%s\n' "$2" | sudo tee "$1" >/dev/null 2>>"$LOG_FILE"; then
    LAST_ERROR="no se pudo escribir $1"
    return 1
  fi
}

# Instala paquetes con dnf y verifica que cada uno quedó instalado. Si alguno
# no existe en los repos, el resto se instala igual y el paso se marca con
# error indicando cuál faltó. Las opciones (--allowerasing…) se pasan a dnf.
pkgs() {
  run sudo dnf install -y --skip-unavailable "$@" || { LAST_ERROR="dnf falló"; return 1; }
  local p missing=()
  for p in "$@"; do
    [[ $p == -* ]] && continue
    rpm -q --whatprovides "$p" &>/dev/null || missing+=("$p")
  done
  if ((${#missing[@]})); then
    LAST_ERROR="no disponibles: ${missing[*]}"
    log "!! $LAST_ERROR"
    return 1
  fi
}

ensure_rpmfusion() {
  local r
  for r in free nonfree; do
    rpm -q "rpmfusion-$r-release" &>/dev/null && continue
    run sudo dnf install -y \
      "https://download1.rpmfusion.org/$r/fedora/rpmfusion-$r-release-$FEDORA_VERSION.noarch.rpm" ||
      { LAST_ERROR="no se pudo instalar RPM Fusion $r"; return 1; }
  done
  rpm -q rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted &>/dev/null ||
    pkgs rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted
}

ensure_flathub() {
  command -v flatpak >/dev/null || pkgs flatpak || return 1
  run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &&
    run sudo flatpak remote-modify --enable --no-filter flathub
}

flatpaks() {
  ensure_flathub || return 1
  run sudo flatpak install -y --noninteractive --or-update --system flathub "$@" ||
    { LAST_ERROR="flatpak falló"; return 1; }
}

# Clona un repositorio o, si ya existe, lo actualiza.
git_sync() {
  if [[ -d $2/.git ]]; then
    run git -C "$2" pull --ff-only
  else
    run git clone --depth=1 "$1" "$2"
  fi
}

detect_gpus() {
  [[ -n $GPU_INFO ]] && return 0
  command -v lspci >/dev/null || pkgs pciutils
  GPU_INFO=$(lspci 2>/dev/null | grep -E 'VGA|3D|Display' || true)
  log "GPUs detectadas: ${GPU_INFO:-ninguna}"
}

newest_kernel() {
  local kernels
  # Si no hay kernel-core (p. ej. en un contenedor), rpm imprime un mensaje
  # en stdout y sale con error: no hay nada que informar.
  kernels=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null) || return 0
  sort -V <<<"$kernels" | tail -n1
}

# ─── Pasos ────────────────────────────────────────────────────────────────────

step_dnf() {
  pkgs dnf5-plugins curl git pciutils || return 1
  run sudo dnf config-manager setopt \
    max_parallel_downloads=20 fastestmirror=True installonly_limit=2 \
    clean_requirements_on_remove=True best=False skip_if_unavailable=True keepcache=False
}

# Con snapper + el plugin "actions" de dnf5, cada instalación o actualización
# crea un snapshot "pre" y otro "post" de /. Si un update rompe algo (p. ej. el
# driver NVIDIA no compila para un kernel nuevo), se restaura desde Btrfs
# Assistant. /home es otro subvolumen: restaurar / no toca tus archivos.
step_snapshots() {
  [[ $(findmnt -no FSTYPE / 2>/dev/null) == btrfs ]] || { skip "/ no está en Btrfs"; return; }
  pkgs snapper libdnf5-plugin-actions btrfs-assistant || return 1
  if [[ ! -f /etc/snapper/configs/root ]]; then
    run sudo snapper -c root create-config / || { LAST_ERROR="snapper create-config falló"; return 1; }
  fi
  # Solo snapshots de dnf (sin los horarios) y se guardan los 10 últimos.
  run sudo snapper -c root set-config NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 TIMELINE_CREATE=no || return 1
  # Ejemplo oficial de libdnf5-actions(8), con "-c number" para que la
  # limpieza automática borre los snapshots viejos.
  # shellcheck disable=SC2016  # ${pid} y ${tmp.*} los expande dnf, no bash
  write_root_file /etc/dnf/libdnf5-plugins/actions.d/snapper.actions '# Generado por fedora-postinstall: snapshot de / antes y después de cada transacción de dnf.
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_descr=$(ps\ -o\ command\ --no-headers\ -p\ '"'"'${pid}'"'"')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ '"'"'${tmp.snapper_descr}'"'"')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ -c\ number\ --pre-number\ "${tmp.snapper_pre_number}"\ -d\ "${tmp.snapper_descr}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.snapper_descr' ||
    { LAST_ERROR="no se pudo crear la acción de snapper para dnf"; return 1; }
  run sudo systemctl enable --now snapper-cleanup.timer || true
}

step_upgrade() {
  run sudo dnf upgrade -y --refresh || return 1
  local k
  k=$(newest_kernel)
  if [[ -n $k && $k != "$(uname -r)" ]]; then
    note "Reinicia el equipo: se instaló un kernel nuevo ($k)."
  fi
}

# Cada editor, dev server o agente que vigila archivos usa "instancias" de
# inotify y el kernel permite solo 128 por usuario: con varios agentes y sus
# dev servers se agotan y el hot-reload deja de funcionar sin avisar.
step_limits() {
  local watches
  watches=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 0)
  ((watches >= 524288)) || watches=524288
  write_root_file /etc/sysctl.d/90-fedora-postinstall.conf "# Generado por fedora-postinstall: margen para editores, dev servers y agentes.
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = $watches" || return 1
  run sudo sysctl -p /etc/sysctl.d/90-fedora-postinstall.conf ||
    note "Los nuevos límites de inotify se aplican al reiniciar."
  return 0
}

step_repos() {
  ensure_rpmfusion || return 1
  ensure_flathub || return 1
  # Codec H.264 de Cisco: viene en un repo de Fedora que a veces está desactivado.
  run sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
}

step_firmware() {
  command -v fwupdmgr >/dev/null || { skip "fwupd no está instalado"; return; }
  run sudo fwupdmgr refresh --force   # si falla, update lo informa igual
  run sudo fwupdmgr update -y --no-reboot-check
  case $? in
    0) note "Reinicia el equipo para aplicar las actualizaciones de firmware." ;;
    2) log "No hay actualizaciones de firmware." ;;
    *) LAST_ERROR="fwupdmgr update falló"; return 1 ;;
  esac
}

step_nvidia() {
  detect_gpus
  [[ $GPU_INFO == *NVIDIA* ]] || { skip "no hay GPU NVIDIA"; return; }
  ensure_rpmfusion || return 1
  pkgs akmod-nvidia xorg-x11-drv-nvidia-cuda || return 1
  # Compila el módulo ya, para el kernel más nuevo; si falla, akmods lo
  # vuelve a intentar solo al arrancar.
  local k
  k=$(newest_kernel)
  [[ -n $k ]] && run sudo akmods --force --kernels "$k"
  note "Reinicia el equipo para cargar el driver NVIDIA."
  if [[ $(mokutil --sb-state 2>/dev/null) == *enabled* ]]; then
    note "Secure Boot está activo: para que el driver NVIDIA cargue, ejecuta 'sudo mokutil --import /etc/pki/akmods/certs/public_key.der', elige una contraseña y, al reiniciar, entra a 'Enroll MOK' con ella."
  fi
  return 0
}

step_multimedia() {
  ensure_rpmfusion || return 1
  # Primero el ffmpeg completo de RPM Fusion: --allowerasing reemplaza
  # ffmpeg-free y sus librerías (libswscale-free…). Si @multimedia va antes,
  # instala esas librerías "free" y luego ffmpeg-libs choca con ellas.
  pkgs --allowerasing ffmpeg ffmpeg-libs libva libva-utils libdvdcss || return 1
  run sudo dnf install -y @multimedia --setopt=install_weak_deps=False \
    --exclude=PackageKit-gstreamer-plugin || { LAST_ERROR="grupo multimedia"; return 1; }
  run sudo dnf group install -y sound-and-video || { LAST_ERROR="grupo sound-and-video"; return 1; }
  # Firmwares extra de rpmfusion-nonfree-tainted. Se listan primero y se
  # instalan con todos los repos activos: con `--repo=...` dnf no ve las
  # dependencias que están en Fedora (bluez, usbutils…) y falla.
  local firmwares
  firmwares=$(dnf repoquery -q --repo=rpmfusion-nonfree-tainted --qf '%{name}\n' '*-firmware' 2>>"$LOG_FILE" | sort -u)
  [[ -n $firmwares ]] || { LAST_ERROR="no se pudo listar los firmwares de rpmfusion-nonfree-tainted"; return 1; }
  # shellcheck disable=SC2086  # una palabra por paquete
  pkgs $firmwares
}

step_hwaccel() {
  detect_gpus
  local done_any=0
  if [[ $GPU_INFO == *Intel* ]]; then
    pkgs intel-media-driver || return 1
    done_any=1
  fi
  if [[ $GPU_INFO == *"AMD/ATI"* || $GPU_INFO == *Radeon* ]]; then
    ensure_rpmfusion || return 1
    # Los drivers de Fedora no traen H.264/H.265; los de RPM Fusion sí.
    pkgs --allowerasing mesa-va-drivers-freeworld || return 1
    done_any=1
  fi
  ((done_any)) || { skip "no hay GPU Intel/AMD que configurar"; return; }
}

step_fonts() {
  pkgs curl cabextract xorg-x11-font-utils fontconfig || return 1
  if ! rpm -q msttcore-fonts-installer &>/dev/null; then
    # El RPM no trae firma ni digest: dnf lo rechaza aun con --nogpgcheck,
    # así que se instala con rpm (las dependencias ya las puso dnf arriba).
    local f
    f=$(download "$MSFONTS_RPM") || return 1
    run sudo rpm -i --nodigest --nosignature "$f" ||
      { LAST_ERROR="msttcore-fonts-installer"; return 1; }
  fi
  install_cambria
}

# Cambria y otras fuentes de Office que no vienen en msttcore.
install_cambria() {
  local dest="$HOME/.local/share/fonts/microsoft"
  [[ -f $dest/.fedora-postinstall ]] && return 0
  local exe dir
  exe=$(download "$PPTVIEWER_URL") || return 1
  if [[ $(sha256sum "$exe" | cut -d' ' -f1) != "$PPTVIEWER_SHA256" ]]; then
    LAST_ERROR="el checksum de PowerPointViewer.exe no coincide"
    return 1
  fi
  dir=$(mktemp -d -p "$WORK_DIR") || return 1
  if ! run cabextract -q -d "$dir" -F ppviewer.cab "$exe" ||
    ! run cabextract -q -d "$dir" -F '*.TTF' -F '*.TTC' "$dir/ppviewer.cab"; then
    LAST_ERROR="no se pudo extraer PowerPointViewer.exe"
    return 1
  fi
  mkdir -p "$dest" &&
    find "$dir" -maxdepth 1 -iname '*.tt[fc]' -exec mv -t "$dest" {} + &&
    run fc-cache -f &&
    touch "$dest/.fedora-postinstall"
}

step_compression() {
  pkgs p7zip p7zip-plugins zstd pigz pbzip2
}

step_latex() {
  pkgs texlive-scheme-full make google-roboto-fonts adobe-source-sans-pro-fonts texlive-fontawesome6
}

step_chrome() {
  [[ $ARCH == x86_64 ]] || { skip "Chrome no existe para $ARCH"; return; }
  pkgs fedora-workstation-repositories || return 1
  run sudo dnf config-manager setopt google-chrome.enabled=1 || return 1
  pkgs google-chrome-stable
}

step_brave() {
  run sudo dnf config-manager addrepo --overwrite \
    --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo ||
    { LAST_ERROR="no se pudo agregar el repo de Brave"; return 1; }
  pkgs brave-browser
}

step_apps() {
  ensure_rpmfusion || return 1
  # obs-studio-plugin-vkcapture: captura juegos Vulkan/OpenGL directo (en
  # Steam: "obs-gamecapture %command%"), sin la latencia de capturar pantalla.
  pkgs vlc gimp obs-studio obs-studio-plugin-vkcapture shotcut
}

step_office() {
  flatpaks org.onlyoffice.desktopeditors
}

step_gaming() {
  local rc=0
  ensure_rpmfusion || return 1
  if [[ $ARCH == x86_64 ]]; then
    pkgs steam || rc=1
  else
    log "Steam solo existe para x86_64; se omite."
  fi
  pkgs gamescope gamemode mangohud goverlay || rc=1
  flatpaks net.davidotek.pupgui2 || rc=1
  return $rc
}

# NTSYNC imita la sincronización de Windows en el kernel; GE-Proton lo usa
# solo si el módulo está cargado. Fedora lo carga junto con el Steam de RPM
# Fusion desde F44; este archivo lo deja cargado siempre.
step_ntsync() {
  modinfo ntsync &>/dev/null || { skip "el kernel no trae el módulo ntsync"; return; }
  write_root_file /etc/modules-load.d/ntsync.conf "ntsync" || return 1
  run sudo modprobe ntsync || { LAST_ERROR="no se pudo cargar el módulo ntsync"; return 1; }
}

# Última versión de GE-Proton, verificada con su sha512, en la carpeta que lee
# el Steam nativo. Las versiones anteriores se conservan.
step_protonge() {
  # Steam (RPM Fusion) solo existe para x86_64, aunque GE-Proton tenga build ARM.
  [[ $ARCH == x86_64 ]] || { skip "Steam no existe para $ARCH"; return; }
  local dest="$HOME/.local/share/Steam/compatibilitytools.d"
  local json tag tar_url sum_url tarball sums expected dir
  command -v python3 >/dev/null || pkgs python3 || return 1
  json=$(curl -fsSL --retry 3 https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>>"$LOG_FILE") ||
    { LAST_ERROR="no se pudo consultar la última versión en GitHub"; return 1; }
  # Los nombres de los archivos cambian entre versiones (GE-Proton11-12-x86_64.tar.gz,
  # antes GE-Proton10-25.tar.gz): se toman de la API en vez de armarlos a mano.
  local pick='
import json, sys
d = json.load(sys.stdin)
tag, arch = d["tag_name"], sys.argv[1]
urls = {a["name"]: a["browser_download_url"] for a in d["assets"]}
for name in (f"{tag}-{arch}.tar.gz", f"{tag}.tar.gz"):
    if name in urls:
        print(tag, urls[name], urls.get(name[:-len(".tar.gz")] + ".sha512sum", "-"))
        break
'
  read -r tag tar_url sum_url < <(python3 -c "$pick" "$ARCH" <<<"$json" 2>>"$LOG_FILE")
  [[ ${tag:-} == GE-Proton* && -n ${tar_url:-} && ${sum_url:--} != - ]] ||
    { LAST_ERROR="no se encontró el archivo de GE-Proton para $ARCH en GitHub"; return 1; }
  # El archivo se descomprime en una carpeta con su mismo nombre
  # (GE-Proton11-12-x86_64), que puede no ser igual al tag.
  dir=${tar_url##*/}
  dir=${dir%.tar.gz}
  if [[ -d $dest/$dir ]]; then
    log "$dir ya está instalado."
    return 0
  fi
  tarball=$(download "$tar_url") || return 1
  sums=$(download "$sum_url") || return 1
  expected=$(cut -d' ' -f1 "$sums")
  if [[ $(sha512sum "$tarball" | cut -d' ' -f1) != "$expected" ]]; then
    LAST_ERROR="el checksum de $tag no coincide"
    return 1
  fi
  if ! mkdir -p "$dest" || ! run tar -xzf "$tarball" -C "$dest"; then
    LAST_ERROR="no se pudo extraer $tag"
    return 1
  fi
  note "GE-Proton listo: en Steam, Propiedades del juego > Compatibilidad > $tag (reinicia Steam si no aparece)."
}

step_devtools() {
  run sudo dnf group install -y development-tools || { LAST_ERROR="grupo development-tools"; return 1; }
  pkgs gcc gcc-c++ make cmake clang patch git pkgconf-pkg-config \
    glibc-devel openssl-devel zlib-devel \
    readline-devel libffi-devel libyaml-devel gdbm-devel ncurses-devel
}

step_cli() {
  pkgs gh ripgrep fd-find fzf jq git-delta lazygit direnv distrobox || return 1
  # delta como visor de diffs de git, solo si no tienes otro configurado.
  if [[ -z $(git config --global --get core.pager 2>/dev/null) ]]; then
    git config --global core.pager delta &&
      git config --global interactive.diffFilter 'delta --color-only' &&
      git config --global delta.navigate true
  fi
}

step_zsh() {
  pkgs zsh git || return 1
  if [[ ! -d $HOME/.oh-my-zsh ]]; then
    local f
    f=$(download https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) || return 1
    # --unattended: no cambia la shell ni abre zsh al terminar (eso colgaba
    # al script anterior).
    run env RUNZSH=no CHSH=no sh "$f" --unattended || { LAST_ERROR="instalador de Oh My Zsh"; return 1; }
  fi
  local custom="$HOME/.oh-my-zsh/custom"
  git_sync https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k" || return 1
  git_sync https://github.com/zsh-users/zsh-autosuggestions "$custom/plugins/zsh-autosuggestions" || return 1
  if [[ -f $HOME/.zshrc ]]; then
    sed -i -e 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' \
      -e 's|^plugins=(.*)|plugins=(git docker zsh-autosuggestions)|' "$HOME/.zshrc"
  fi
  # La ruta tiene que ser la que figura en /etc/shells (/usr/bin/zsh); con
  # /usr/sbin/zsh, que en Fedora 42+ es la misma, GDM puede rechazar el login.
  local zsh_path
  zsh_path=$(grep -m1 -E '^/usr/bin/zsh$|^/bin/zsh$' /etc/shells) || zsh_path=/usr/bin/zsh
  if [[ $(getent passwd "$USER_NAME" | cut -d: -f7) != "$zsh_path" ]]; then
    run sudo usermod --shell "$zsh_path" "$USER_NAME" || return 1
    note "Cierra sesión y vuelve a entrar para usar Zsh (la primera vez Powerlevel10k te ofrecerá configurarlo)."
  fi
}

step_ghostty() {
  run sudo dnf copr enable -y scottames/ghostty ||
    { LAST_ERROR="el COPR de Ghostty no tiene paquetes para Fedora $FEDORA_VERSION"; return 1; }
  pkgs ghostty
}

step_rust() {
  if [[ -x $HOME/.cargo/bin/rustup ]]; then
    run "$HOME/.cargo/bin/rustup" update
    return
  fi
  local f
  f=$(download https://sh.rustup.rs) || return 1
  # El PATH lo agrega el paso "env".
  run sh "$f" -y --no-modify-path
}

step_go() {
  local arch latest f
  case $ARCH in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) skip "arquitectura $ARCH no soportada"; return ;;
  esac
  latest=$(curl -fsSL --retry 3 'https://go.dev/VERSION?m=text' 2>>"$LOG_FILE") ||
    { LAST_ERROR="no se pudo consultar la última versión en go.dev"; return 1; }
  latest=${latest%%$'\n'*}
  [[ $latest == go1.* ]] || { LAST_ERROR="respuesta inesperada de go.dev: $latest"; return 1; }
  if [[ -x /usr/local/go/bin/go && $(/usr/local/go/bin/go env GOVERSION 2>/dev/null) == "$latest" ]]; then
    log "$latest ya está instalado."
    return 0
  fi
  f=$(download "https://go.dev/dl/$latest.linux-$arch.tar.gz") || return 1
  run sudo rm -rf /usr/local/go && run sudo tar -C /usr/local -xzf "$f"
}

step_node() {
  if [[ ! -s $HOME/.nvm/nvm.sh ]]; then
    local f
    f=$(download "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh") || return 1
    # PROFILE=/dev/null: no toca .bashrc/.zshrc; el paso "env" carga NVM.
    run env PROFILE=/dev/null bash "$f" || { LAST_ERROR="instalador de NVM"; return 1; }
  fi
  # shellcheck disable=SC2016  # $HOME se expande dentro del bash hijo
  run bash -c 'source "$HOME/.nvm/nvm.sh" && nvm install --lts && nvm alias default "lts/*"'
}

step_uv() {
  if [[ -x $HOME/.local/bin/uv ]]; then
    run "$HOME/.local/bin/uv" self update
    return
  fi
  local f
  f=$(download https://astral.sh/uv/install.sh) || return 1
  run env UV_NO_MODIFY_PATH=1 sh "$f"
}

step_docker() {
  local probe="https://download.docker.com/linux/fedora/$FEDORA_VERSION/$ARCH/stable/repodata/repomd.xml"
  if rpm -q docker-ce &>/dev/null || curl -fsIL --retry 2 -o /dev/null "$probe" 2>/dev/null; then
    run sudo dnf config-manager addrepo --overwrite \
      --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo ||
      { LAST_ERROR="no se pudo agregar el repo de Docker"; return 1; }
    pkgs --allowerasing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  else
    # Docker suele tardar unas semanas en publicar paquetes para una Fedora nueva.
    pkgs moby-engine docker-compose || return 1
    note "Docker aún no publica paquetes para Fedora $FEDORA_VERSION: quedó instalado moby-engine (el Docker de Fedora). Vuelve a ejecutar el script más adelante para pasar a docker-ce."
  fi
  getent group docker >/dev/null || run sudo groupadd docker
  run sudo systemctl enable --now docker || { LAST_ERROR="no se pudo iniciar el servicio docker"; return 1; }
  if [[ " $(id -nG "$USER_NAME") " != *" docker "* ]]; then
    run sudo usermod -aG docker "$USER_NAME" || return 1
    note "Cierra sesión y vuelve a entrar para usar docker sin sudo."
  fi
}

step_zed() {
  local f
  f=$(download https://zed.dev/install.sh) || return 1
  run sh "$f"
}

step_cursor() {
  write_root_file /etc/yum.repos.d/cursor.repo "[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc" || { LAST_ERROR="no se pudo crear el repo de Cursor"; return 1; }
  pkgs cursor
}

step_dbeaver() {
  flatpaks io.dbeaver.DBeaverCommunity
}

step_claude() {
  local f
  f=$(download https://claude.ai/install.sh) || return 1
  run bash "$f"
}

step_opencode() {
  local f
  f=$(download https://opencode.ai/install) || return 1
  run bash "$f"
}

step_herdr() {
  local f
  f=$(download https://herdr.dev/install.sh) || return 1
  # Deja el binario en ~/.local/bin (el paso "env" ya lo agrega al PATH).
  run sh "$f"
}

step_obsidian() {
  flatpaks md.obsidian.Obsidian
}

# Un único bloque en .bashrc y .zshrc con el PATH de todo lo instalado en el
# home. Se reemplaza completo en cada ejecución, así nunca se duplica.
step_env() {
  local f block
  block=$(
    cat <<'EOF'
# >>> fedora-postinstall >>>
# Generado por fedora-postinstall: se reescribe en cada ejecución.
export GOROOT=/usr/local/go
export GOPATH="$HOME/go"
export NVM_DIR="$HOME/.nvm"
for _d in "$HOME/.local/bin" "$HOME/.cargo/bin" "$GOPATH/bin" "$GOROOT/bin" "$HOME/.opencode/bin"; do
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$_d:$PATH" ;; esac
done
unset _d
export PATH
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
# direnv (variables por proyecto) y fzf (Ctrl-R: buscar en el historial).
if [ -n "${ZSH_VERSION:-}" ]; then _sh=zsh; else _sh=bash; fi
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook $_sh)"
command -v fzf >/dev/null 2>&1 && eval "$(fzf --$_sh)"
unset _sh
# <<< fedora-postinstall <<<
EOF
  )
  for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f $f ]] || continue
    sed -i '/^# >>> fedora-postinstall >>>$/,/^# <<< fedora-postinstall <<<$/d' "$f" || return 1
    printf '%s\n' "$block" >>"$f"
  done
}

# ─── Orquestación ─────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Fedora PostInstall: instala todo sin preguntar.

Uso:
  curl -fsSL $REPO_RAW | bash
  curl -fsSL $REPO_RAW | bash -s -- [opciones]

Opciones:
  --list          Muestra los pasos disponibles.
  --only a,b,c    Ejecuta solo esos pasos.
  --skip a,b,c    Ejecuta todo menos esos pasos.
  -h, --help      Muestra esta ayuda.
EOF
}

list_steps() {
  local s
  for s in "${STEPS[@]}"; do printf '  %-12s %s\n' "${s%%|*}" "${s#*|}"; done
}

valid_ids() {
  local id s found
  for id in ${1//,/ }; do
    found=0
    for s in "${STEPS[@]}"; do [[ ${s%%|*} == "$id" ]] && found=1; done
    ((found)) || die "Paso desconocido: '$id'. Usa --list para ver los pasos."
  done
}

parse_args() {
  while (($#)); do
    case $1 in
      --only) [[ $# -ge 2 ]] || die "--only necesita una lista de pasos"; ONLY=$2; shift 2 ;;
      --only=*) ONLY=${1#*=}; shift ;;
      --skip) [[ $# -ge 2 ]] || die "--skip necesita una lista de pasos"; SKIP=$2; shift 2 ;;
      --skip=*) SKIP=${1#*=}; shift ;;
      --list) list_steps; exit 0 ;;
      -h | --help) usage; exit 0 ;;
      *) die "Opción desconocida: $1 (usa --help)" ;;
    esac
  done
  valid_ids "$ONLY"
  valid_ids "$SKIP"
}

selected() {
  local id=$1
  [[ ",$SKIP," == *",$id,"* ]] && return 1
  [[ -z $ONLY || $id == env ]] && return 0   # env siempre, salvo --skip env
  [[ ",$ONLY," == *",$id,"* ]]
}

cleanup() {
  local pid
  for pid in "${BG_PIDS[@]}"; do kill "$pid" 2>/dev/null; done
  [[ -n $WORK_DIR ]] && rm -rf "$WORK_DIR"
}

preflight() {
  [[ $EUID -ne 0 ]] || die "No lo ejecutes como root ni con sudo: córrelo con tu usuario, pedirá sudo cuando haga falta."
  local distro
  # shellcheck disable=SC1091
  distro=$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")
  [[ $distro == fedora ]] || die "Este script es solo para Fedora."
  [[ ! -e /run/ostree-booted ]] || die "Fedora Atomic (Silverblue, Kinoite…) no está soportado: ahí se instala con rpm-ostree."
  FEDORA_VERSION=$(rpm -E %fedora)
  [[ $FEDORA_VERSION =~ ^[0-9]+$ ]] || die "No se pudo detectar la versión de Fedora."
  ((FEDORA_VERSION >= MIN_FEDORA)) || die "Fedora $FEDORA_VERSION ya no está soportada (mínimo $MIN_FEDORA). Actualiza Fedora primero."
  command -v sudo >/dev/null || die "sudo no está instalado."
  command -v curl >/dev/null || die "curl no está instalado."
  curl -fsS --max-time 20 -o /dev/null https://fedoraproject.org || die "Sin conexión a internet."

  : >"$LOG_FILE" || die "No se pudo crear el log en $LOG_FILE"
  WORK_DIR=$(mktemp -d) || die "No se pudo crear un directorio temporal."
  trap cleanup EXIT

  if ! sudo -n true 2>/dev/null; then
    say "Se necesita tu contraseña de sudo (solo esta vez):"
  fi
  sudo -v || die "No se pudo obtener permisos de sudo."
  # Mantiene sudo activo mientras dure la instalación (puede tardar bastante).
  (while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done) >/dev/null 2>&1 &
  BG_PIDS+=("$!")
  # Evita que el equipo se suspenda a mitad de la instalación.
  if command -v systemd-inhibit >/dev/null; then
    systemd-inhibit --what=idle:sleep --who=fedora-postinstall --why="Instalando paquetes" \
      sleep infinity >/dev/null 2>&1 &
    BG_PIDS+=("$!")
  fi
}

run_step() {
  local id=$1 desc=$2 rc start=$SECONDS
  SKIP_REASON="" LAST_ERROR=""
  printf '%s▸%s %s … ' "$C_BLUE" "$C_RESET" "$desc"
  log ""
  log "===== [$id] $desc ====="
  "step_$id"
  rc=$?
  case $rc in
    0)
      printf '%s✓%s %s(%ss)%s\n' "$C_GREEN" "$C_RESET" "$C_DIM" "$((SECONDS - start))" "$C_RESET"
      OK+=("$id")
      ;;
    99)
      printf '%s– omitido: %s%s\n' "$C_DIM" "$SKIP_REASON" "$C_RESET"
      SKIPPED+=("$desc: $SKIP_REASON")
      ;;
    *)
      printf '%s✗ falló%s %s\n' "$C_RED" "$C_RESET" "${LAST_ERROR:+($LAST_ERROR)}"
      FAILED+=("$desc${LAST_ERROR:+ — $LAST_ERROR}  [log: ===== [$id]]")
      FAILED_IDS+=("$id")
      log "!! Paso '$id' falló (código $rc)"
      ;;
  esac
}

summary() {
  local item ids
  say ""
  say "${C_BOLD}Resumen:${C_RESET} ${C_GREEN}${#OK[@]} correctos${C_RESET}, ${C_RED}${#FAILED[@]} con errores${C_RESET}, ${#SKIPPED[@]} omitidos"
  for item in "${FAILED[@]}"; do say "  ${C_RED}✗${C_RESET} $item"; done
  for item in "${SKIPPED[@]}"; do say "  ${C_DIM}– $item${C_RESET}"; done
  if ((${#NOTES[@]})); then
    say ""
    say "${C_BOLD}Pendiente:${C_RESET}"
    for item in "${NOTES[@]}"; do say "  ${C_YELLOW}•${C_RESET} $item"; done
  fi
  say ""
  say "Log completo: $LOG_FILE"
  if ((${#FAILED_IDS[@]})); then
    ids=$(IFS=,; printf '%s' "${FAILED_IDS[*]}")
    say "Para reintentar solo lo que falló:"
    say "  curl -fsSL $REPO_RAW | bash -s -- --only $ids"
  fi
}

main() {
  parse_args "$@"
  preflight

  say ""
  say "${C_BOLD}Fedora PostInstall${C_RESET} · Fedora $FEDORA_VERSION · $ARCH"
  if ((FEDORA_VERSION > MAX_TESTED_FEDORA)); then
    say "${C_YELLOW}Aviso:${C_RESET} Fedora $FEDORA_VERSION todavía no está probada con este script; sigo igual."
  fi
  say "${C_DIM}Detalle en vivo desde otra terminal: tail -f $LOG_FILE${C_RESET}"
  say ""

  local s
  for s in "${STEPS[@]}"; do
    selected "${s%%|*}" && run_step "${s%%|*}" "${s#*|}"
  done

  summary
  ((${#FAILED[@]} == 0))
}

main "$@"
