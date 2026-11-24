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
readonly NVM_VERSION="v0.41.0"
readonly MSFONTS_RPM="https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm"
readonly MSFONTS_SHA256="55d7f3a86533225634ff3ea2384b4356d9665a29cc7eeacff16602a1714afbb4"
readonly PPTVIEWER_URL="https://archive.org/download/PowerPointViewer_201801/PowerPointViewer.exe"
readonly PPTVIEWER_SHA256="249473568eba7a1e4f95498acba594e0f42e6581add4dead70c1dfb908a09423"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fedora-postinstall"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
ARCH="$(uname -m)"
USER_NAME="$(id -un)"
FEDORA_VERSION=""
WORK_DIR=""
BG_PIDS=()
GPU_INFO=""
SKIP_REASON=""
LAST_ERROR=""
ONLY=""
LAST_CMD=""
CURRENT_STEP=""
DL=""
ON_BATTERY=0
SNAPPER_HOOK_PENDING=0
declare -A STEP_OFFSET=()
SKIP=""
NOTES=()
OK=()
FAILED=()
FAILED_IDS=()
SKIPPED=()

# id|descripción — se ejecutan en este orden. La función de cada paso es
# step_<id>. Las entradas "@Nombre" son títulos de sección para la pantalla.
STEPS=(
  "@Sistema"
  "dnf|Optimizar DNF y herramientas base"
  "snapshots|Snapshots automáticos antes de cada dnf (Btrfs)"
  "upgrade|Actualizar el sistema"
  "limits|Límites de inotify para editores y agentes"
  "repos|Repositorios RPM Fusion y Flathub"
  "firmware|Firmware (LVFS)"
  "@Hardware"
  "nvidia|Drivers NVIDIA"
  "hwaccel|Aceleración de video por hardware"
  "@Escritorio"
  "extensions|Extension Manager (extensiones de GNOME)"
  "@Multimedia y apps"
  "multimedia|Codecs multimedia"
  "fonts|Fuentes de Microsoft"
  "compression|Herramientas de compresión"
  "chrome|Google Chrome"
  "brave|Brave"
  "apps|VLC, GIMP, OBS Studio (+ captura de juegos), Shotcut"
  "office|ONLYOFFICE (Flatpak)"
  "@Gaming"
  "gaming|Steam, Gamescope, GameMode, MangoHud y ProtonUp-Qt"
  "ntsync|NTSYNC para juegos (Wine/GE-Proton)"
  "protonge|GE-Proton (última versión)"
  "@Desarrollo"
  "devtools|Herramientas de desarrollo"
  "cli|CLI para agentes (gh, ripgrep, fd, fzf, jq, delta, lazygit, direnv, distrobox)"
  "zsh|Zsh + Oh My Zsh + Powerlevel10k"
  "env|Variables de entorno (PATH, Go, NVM, direnv, fzf)"
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
  "@Documentos"
  "latex|LaTeX completo (el paso más pesado: varios GB)"
)

# Animación y barra de progreso solo en una terminal interactiva. Si la salida
# va a un archivo o a otro programa, se imprimen líneas simples sin colores.
UI_LIVE=0
if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
  UI_LIVE=1
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
  C_GREEN=$'\e[32m' C_RED=$'\e[31m' C_YELLOW=$'\e[33m' C_ACCENT=$'\e[38;5;39m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_GREEN="" C_RED="" C_YELLOW="" C_ACCENT=""
fi
LC_CTYPE=C.UTF-8 # para que ${#texto} cuente caracteres y no bytes al alinear
# Progreso en la barra de tareas (OSC 9;4): solo en terminales que lo entienden;
# en otras, OSC 9 puede mostrarse como notificación.
OSC_PROGRESS=0
[[ ${TERM_PROGRAM:-} == ghostty || -n ${VTE_VERSION:-} || -n ${WT_SESSION:-} ]] && OSC_PROGRESS=1
SPINNER='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
[[ ${TERM:-} == linux ]] && SPINNER='-\|/' # la consola de texto no tiene braille
UI_PID=""
STATUS_FILE=""
RUN_START=0
STEP_NUM=0
STEP_TOTAL=0

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
# RUN_LABEL (opcional, con `local` en quien llama) es lo que se muestra en
# pantalla en vez del comando.
run() {
  local cmd="$*" offset
  LAST_CMD=${cmd#sudo }
  log "\$ $cmd"
  offset=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
  status "${RUN_LABEL:-$LAST_CMD}" "" "$offset"
  "$@" </dev/null >>"$LOG_FILE" 2>&1
}

# Descarga una URL a un archivo temporal y deja la ruta en $DL (no se usa
# $(download …) porque el subshell perdería LAST_ERROR). Los instaladores
# oficiales (rustup, uv, nvm…) se bajan primero y se ejecutan después, en vez
# de `curl | sh`, para detectar una descarga fallida antes de ejecutar nada.
# Reintenta cortes y aborta si la descarga se estanca 60 s.
CURL_OPTS=(-fsSL --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 20 --speed-limit 1024 --speed-time 60)
download() {
  DL=$(mktemp -p "$WORK_DIR") || return 1
  log "\$ curl $1"
  status "descargando ${1#*://}" "$DL" ""
  curl "${CURL_OPTS[@]}" -o "$DL" "$1" >>"$LOG_FILE" 2>&1 || {
    LAST_ERROR="no se pudo descargar ${1#*://}"
    return 1
  }
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
  local offset p missing=()
  offset=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
  local names=""
  for p in "$@"; do [[ $p == -* ]] || names+=" $p"; done # sin opciones, para la pantalla
  local RUN_LABEL="${RUN_LABEL:-dnf: instalando$names}"
  if ! run sudo dnf install -y --skip-unavailable "$@"; then
    LAST_ERROR="dnf: $(log_hint "$offset")"
    return 1
  fi
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

# Primera línea de error que dejó en el log lo ejecutado desde `offset`.
log_hint() {
  local hint
  hint=$(tail -c +$(($1 + 1)) "$LOG_FILE" 2>/dev/null |
    grep -m1 -E 'Problem|No match|nothing provides|conflicts|[Ee]rror|[Ff]ailed' | sed 's/^ *//; s/^- *//')
  printf '%s' "${hint:-revisa el log}"
}

ensure_rpmfusion() {
  local r key keys=/usr/share/distribution-gpg-keys/rpmfusion
  for r in free nonfree; do
    rpm -q "rpmfusion-$r-release" &>/dev/null && continue
    # El RPM del repo se baja de internet: se verifica su firma con la llave
    # que publica Fedora en distribution-gpg-keys antes de instalarlo.
    key="$keys/RPM-GPG-KEY-rpmfusion-$r-fedora-$FEDORA_VERSION"
    [[ -f $key ]] || pkgs distribution-gpg-keys || return 1
    [[ -f $key ]] || { LAST_ERROR="no está la llave de RPM Fusion $r para Fedora $FEDORA_VERSION"; return 1; }
    if ! run sudo rpmkeys --import "$key" ||
      ! run sudo dnf install -y --setopt=localpkg_gpgcheck=1 \
        "https://download1.rpmfusion.org/$r/fedora/rpmfusion-$r-release-$FEDORA_VERSION.noarch.rpm"; then
      LAST_ERROR="no se pudo instalar RPM Fusion $r"
      return 1
    fi
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
  local RUN_LABEL="flatpak: instalando ${*##*.}"
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

# ─── Interfaz ─────────────────────────────────────────────────────────────────
#
# Mientras corre un paso, un proceso aparte redibuja dos líneas al pie:
#
#   ⠹ Codecs multimedia · instalando ffmpeg-libs (45/120)        0:23
#   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  8/36 · 22% · 4:32
#
# "Qué está haciendo" sale de STATUS_FILE (lo escriben run y download) y, en
# los comandos de dnf, del progreso que dnf va dejando en el log.

# Deja constancia de lo que se está haciendo, para mostrarlo en pantalla.
# status <texto> [<archivo que se está descargando>] [<offset del log>]
status() {
  # Separador \x1f y no tabulación: `read` junta tabulaciones seguidas y un
  # campo vacío desplazaría a los demás.
  [[ -n $STATUS_FILE ]] && printf '%s\x1f%s\x1f%s' "$1" "${2:-}" "${3:-}" >"$STATUS_FILE" 2>/dev/null
  return 0
}

ui_cols() {
  local cols=""
  ((UI_LIVE)) && read -r _ cols < <(stty size </dev/tty 2>/dev/null)
  [[ $cols =~ ^[0-9]+$ ]] || cols=80
  ((cols > 100)) && cols=100
  printf '%s' "$cols"
}

fmt_time() {
  _fmt_time "$1"
  printf '%s' "$_R"
}

# Las variantes _x dejan el resultado en $_R sin abrir un subshell: la
# animación se redibuja 10 veces por segundo y así no lanza procesos.
_fmt_time() {
  local s=$1
  if ((s >= 3600)); then
    printf -v _R '%d:%02d:%02d' $((s / 3600)) $((s % 3600 / 60)) $((s % 60))
  else
    printf -v _R '%d:%02d' $((s / 60)) $((s % 60))
  fi
}

# repeat <texto> <veces>
repeat() {
  _repeat "$1" "$2"
  printf '%s' "$_R"
}

_repeat() {
  local i
  _R=""
  for ((i = 0; i < $2; i++)); do _R+=$1; done
}

# trunc <texto> <ancho máximo>
trunc() {
  _trunc "$1" "$2"
  printf '%s' "$_R"
}

_trunc() {
  local text=$1 max=$2
  if ((max <= 0)); then
    _R=""
  elif ((${#text} > max)); then
    _R="${text:0:max-1}…"
  else
    _R=$text
  fi
}

# ui_bar <hechos> <total> <ancho>
_ui_bar() {
  local done=$1 total=$2 width=$3 fill a b
  ((total > 0)) || total=1
  fill=$((done * width / total))
  _repeat '━' "$fill"
  a=$_R
  _repeat '━' $((width - fill))
  b=$_R
  _R="${C_ACCENT}${a}${C_DIM}${b}${C_RESET}"
}

# Traduce el estado actual a algo legible: progreso de dnf, MB descargados o
# el comando que se está ejecutando.
ui_detail() {
  local text path offset size line rest phase
  IFS=$'\x1f' read -r text path offset <<<"$1"
  if [[ -n $path ]]; then
    size=$(stat -c %s "$path" 2>/dev/null || echo 0)
    if ((size >= 1048576)); then
      printf '%s · %s MB' "$text" $((size / 1048576))
    else
      printf '%s · %s KB' "$text" $((size / 1024))
    fi
    return
  fi
  if [[ -n $offset ]]; then
    # Solo lo que escribió ESTE comando de dnf, no el anterior.
    line=$(tail -c +$((offset + 1)) "$LOG_FILE" 2>/dev/null | tail -c 6000 | tr '\r' '\n' |
      grep -E '^\[ *[0-9]+/[0-9]+\]|^Running transaction' | tail -n1)
    if [[ $line == "Running transaction"* ]]; then
      printf 'instalando paquetes…'
      return
    fi
    if [[ $line =~ ^\[\ *([0-9]+)/([0-9]+)\]\ +(.*)$ ]]; then
      rest=${BASH_REMATCH[3]}
      rest=${rest%-[0-9]*:*} # quita versión: ffmpeg-libs-0:7.1-1.fc45 → ffmpeg-libs
      local verb=${rest%% *} pkg=${rest#* }
      pkg=${pkg%% *} # solo el nombre, sin las columnas de velocidad de dnf
      case $verb in
        Installing) phase="instalando $pkg" ;;
        Upgrading) phase="actualizando $pkg" ;;
        Removing) phase="quitando $pkg" ;;
        Verify) phase="verificando paquetes" ;;
        Prepare) phase="preparando la transacción" ;;
        Total) phase="descarga completa" ;;
        *) phase="descargando $verb" ;;
      esac
      printf '%s (%s/%s)' "$phase" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      return
    fi
  fi
  printf '%s' "$text"
}

# Proceso que redibuja las dos líneas de abajo cada 0,1 s hasta que lo matan.
ui_ticker() {
  local desc=$1 t0=$2 i=0 cols=80 detail="" el total left det room pct info barw pad bar
  local frames=${#SPINNER}
  # Al recibir la orden de parar, termina el cuadro que está dibujando: si se
  # cortara a la mitad, el cursor quedaría una línea más abajo y el borrado
  # dejaría una línea fantasma.
  trap 'exit 0' TERM
  while kill -0 "$$" 2>/dev/null; do # si el script muere, la animación también
    if ((i % 5 == 0)); then
      cols=$(ui_cols)
      detail=$(ui_detail "$(cat "$STATUS_FILE" 2>/dev/null)")
    fi
    _fmt_time $((EPOCHSECONDS - t0)); el=$_R
    _fmt_time $((EPOCHSECONDS - RUN_START)); total=$_R
    # Línea 1: animación, paso, detalle y tiempo del paso alineado a la derecha.
    room=$((cols - 10 - ${#el}))
    _trunc "$desc" "$room"; left=$_R
    det=""
    if [[ -n $detail ]] && ((room - ${#left} > 12)); then
      _trunc "$detail" $((room - ${#left} - 3)); det=" · $_R"
    fi
    _repeat ' ' $((cols - 8 - ${#left} - ${#det} - ${#el})); pad=$_R
    # Línea 2: barra general.
    pct=$(((STEP_NUM - 1) * 100 / STEP_TOTAL))
    info="  $STEP_NUM/$STEP_TOTAL · $pct% · $total"
    barw=$((cols - 6 - ${#info}))
    _ui_bar $((STEP_NUM - 1)) "$STEP_TOTAL" "$barw"; bar=$_R
    printf '\r\e[2K    %s%s%s %s%s%s%s%s%s%s\n\e[2K    %s%s%s%s\e[1A\r' \
      "$C_ACCENT" "${SPINNER:i%frames:1}" "$C_RESET" "$left" "$C_DIM" "$det" "$C_RESET" \
      "$pad" "$C_DIM$el" "$C_RESET" "$bar" "$C_DIM" "$info" "$C_RESET"
    i=$((i + 1))
    sleep 0.1
  done
}

ui_step_start() {
  local desc=$1 pct
  pct=$(((STEP_NUM - 1) * 100 / STEP_TOTAL))
  status ""
  if ((UI_LIVE)); then
    printf '\e]0;Fedora PostInstall · %s/%s\a' "$STEP_NUM" "$STEP_TOTAL"
    ((OSC_PROGRESS)) && printf '\e]9;4;1;%s\a' "$pct"
    ui_ticker "$desc" "$EPOCHSECONDS" &
    UI_PID=$!
  else
    printf '[%s/%s] %s…\n' "$STEP_NUM" "$STEP_TOTAL" "$desc"
  fi
}

ui_step_stop() {
  [[ -n $UI_PID ]] || return 0
  kill "$UI_PID" 2>/dev/null
  wait "$UI_PID" 2>/dev/null
  UI_PID=""
  printf '\r\e[2K\n\e[2K\e[1A\r'
}

# ui_result <icono> <color> <texto> <dato a la derecha>
ui_result() {
  local icon=$1 color=$2 text=$3 info=$4 cols width dots
  cols=$(ui_cols)
  width=$((cols - 8))
  # Si no cabe, se acorta primero el dato de la derecha (un error largo) y
  # después el nombre del paso, que nunca queda vacío.
  info=$(trunc "$info" $((width / 2)))
  text=$(trunc "$text" $((width - ${#info} - 3)))
  dots=$((width - ${#text} - ${#info} - 2))
  ((dots < 1)) && dots=1
  printf '    %s%s%s %s %s%s%s %s%s%s\n' "$color" "$icon" "$C_RESET" "$text" \
    "$C_DIM" "$(repeat '·' "$dots")" "$C_RESET" "$color" "$info" "$C_RESET"
}

# Recuadro de bienvenida con los datos del equipo.
ui_banner() {
  local cols width gpu cpus ram free l
  cols=$(ui_cols)
  width=$((cols - 6))
  cpus=$(nproc 2>/dev/null || echo "?")
  ram=$(awk '/^MemTotal/ {printf "%d", $2 / 1048576 + 0.5}' /proc/meminfo 2>/dev/null)
  free=$(df -BG --output=avail / 2>/dev/null | awk 'NR == 2 {gsub("G", ""); print $1}')
  gpu=$(lspci 2>/dev/null | grep -E 'VGA|3D|Display' | sed -E 's/^[^:]+: [^:]+: //; s/ \(rev [^)]*\)//' | paste -sd '+' | sed 's/+/ + /g')
  local lines=("Fedora $FEDORA_VERSION · $ARCH · $cpus núcleos · ${ram:-?} GB RAM · ${free:-?} GB libres")
  [[ -n $gpu ]] && lines+=("GPU: $gpu")
  say ""
  say "  ${C_ACCENT}╭$(repeat '─' "$width")╮${C_RESET}"
  say "  ${C_ACCENT}│${C_RESET}  ${C_BOLD}Fedora PostInstall${C_RESET}$(repeat ' ' $((width - 20)))${C_ACCENT}│${C_RESET}"
  for l in "${lines[@]}"; do
    l=$(trunc "$l" $((width - 4)))
    say "  ${C_ACCENT}│${C_RESET}  ${C_DIM}${l}${C_RESET}$(repeat ' ' $((width - 2 - ${#l})))${C_ACCENT}│${C_RESET}"
  done
  say "  ${C_ACCENT}╰$(repeat '─' "$width")╯${C_RESET}"
  if ((free > 0 && free < 30)); then
    say "  ${C_YELLOW}⚠ Quedan ${free} GB libres; la instalación completa usa unos 20-25 GB (LaTeX y Steam son lo más pesado).${C_RESET}"
  fi
  if ((ON_BATTERY)); then
    say "  ${C_YELLOW}⚠ El equipo está con batería: conecta el cargador. El firmware no se actualizará sin él.${C_RESET}"
  fi
}

# ─── Pasos ────────────────────────────────────────────────────────────────────

step_dnf() {
  pkgs dnf5-plugins curl git pciutils || return 1
  run sudo dnf config-manager setopt \
    max_parallel_downloads=20 fastestmirror=True installonly_limit=3 \
    clean_requirements_on_remove=True best=False skip_if_unavailable=True keepcache=False
}

# Snapshots de / con snapper. Este paso guarda uno solo, "antes de
# fedora-postinstall", y al final de la instalación activa el plugin
# "actions" de dnf5: desde ahí cada dnf crea un snapshot "pre" y otro "post".
# (Activarlo ahora dejaría ~60 snapshots de esta misma instalación.)
# /home es otro subvolumen: restaurar / no toca tus archivos.
step_snapshots() {
  [[ $(findmnt -no FSTYPE / 2>/dev/null) == btrfs ]] || { skip "/ no está en Btrfs"; return; }
  pkgs snapper libdnf5-plugin-actions btrfs-assistant || return 1
  if [[ ! -f /etc/snapper/configs/root ]]; then
    run sudo snapper -c root create-config / || { LAST_ERROR="snapper create-config falló"; return 1; }
  fi
  # Solo snapshots de dnf (sin los horarios) y se guardan los 10 últimos.
  run sudo snapper -c root set-config NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 TIMELINE_CREATE=no || return 1
  run sudo snapper -c root create -c number --userdata important=yes -d "antes de fedora-postinstall" ||
    { LAST_ERROR="no se pudo crear el snapshot inicial"; return 1; }
  run sudo systemctl enable --now snapper-cleanup.timer || true
  SNAPPER_HOOK_PENDING=1
}

# Ejemplo oficial de libdnf5-actions(8), con "-c number" para que la limpieza
# automática borre los snapshots viejos. Se llama al terminar (o al cortar).
install_snapper_hook() {
  ((SNAPPER_HOOK_PENDING)) || return 0
  SNAPPER_HOOK_PENDING=0
  # shellcheck disable=SC2016  # ${pid} y ${tmp.*} los expande dnf, no bash
  write_root_file /etc/dnf/libdnf5-plugins/actions.d/snapper.actions '# Generado por fedora-postinstall: snapshot de / antes y después de cada transacción de dnf.
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_descr=$(ps\ -o\ command\ --no-headers\ -p\ '"'"'${pid}'"'"')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ '"'"'${tmp.snapper_descr}'"'"')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ -c\ number\ --pre-number\ "${tmp.snapper_pre_number}"\ -d\ "${tmp.snapper_descr}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.snapper_descr' ||
    note "No se pudo activar el snapshot automático de dnf (revisa el log)."
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
  ((ON_BATTERY)) && { skip "con batería: conecta el cargador y vuelve a ejecutar"; return; }
  run sudo fwupdmgr refresh --force # si falla, update lo informa igual
  run sudo fwupdmgr update -y --no-reboot-check
  case $? in
    0) note "Al reiniciar se instalará el firmware (puede tardar unos minutos): mantén el equipo enchufado y no lo apagues." ;;
    2) log "No hay actualizaciones de firmware." ;;
    *) LAST_ERROR="fwupdmgr update falló"; return 1 ;;
  esac
}

step_nvidia() {
  detect_gpus
  local nv series="" akmod=akmod-nvidia xorg=xorg-x11-drv-nvidia cuda=xorg-x11-drv-nvidia-cuda
  local sb=0 k key=/etc/pki/akmods/certs/public_key.der
  nv=$(grep NVIDIA <<<"$GPU_INFO")
  [[ -n $nv ]] || { skip "no hay GPU NVIDIA"; return; }
  ensure_rpmfusion || return 1
  # El driver actual ya no soporta GPU antiguas: Kepler (GK…) necesita la
  # serie 470 y, desde Fedora 44, Maxwell/Pascal/Volta (GM…, GP…, GV…) la 580.
  if [[ $nv =~ \ GK[0-9]{2,3} ]]; then
    series=470xx
  elif ((FEDORA_VERSION >= 44)) && [[ $nv =~ \ G[MPV][0-9]{2,3} ]]; then
    series=580xx
  fi
  if [[ -n $series ]]; then
    akmod+="-$series" xorg+="-$series" cuda="xorg-x11-drv-nvidia-$series-cuda"
    log "GPU NVIDIA antigua: se usa la serie $series del driver."
  fi
  [[ $(mokutil --sb-state 2>/dev/null) == *enabled* ]] && sb=1
  # Con Secure Boot, la llave de akmods tiene que existir ANTES de compilar el
  # módulo: si no, queda sin firmar y el kernel lo rechaza (pantalla negra).
  if ((sb)); then
    pkgs akmods mokutil || return 1
    [[ -e $key ]] || run sudo kmodgenca -a || { LAST_ERROR="no se pudo crear la llave de akmods"; return 1; }
  fi
  pkgs "$akmod" "$xorg" "$cuda" || return 1
  k=$(newest_kernel)
  if [[ -n $k ]]; then
    if ! modinfo -k "$k" nvidia &>/dev/null || { ((sb)) && [[ -z $(modinfo -k "$k" -F signer nvidia 2>/dev/null) ]]; }; then
      local RUN_LABEL="compilando el módulo NVIDIA (puede tardar varios minutos)"
      run sudo akmods --force --kernels "$k"
    fi
    modinfo -k "$k" nvidia &>/dev/null ||
      note "El módulo NVIDIA no compiló para el kernel $k (akmods lo reintenta al arrancar; detalle en /var/cache/akmods/nvidia/)."
  fi
  [[ -e /proc/driver/nvidia/version ]] || note "Reinicia el equipo para cargar el driver NVIDIA."
  if ((sb)) && [[ $(mokutil --test-key "$key" 2>&1) != *"already enrolled"* ]]; then
    note "Secure Boot: ANTES de reiniciar ejecuta 'sudo mokutil --import $key' y elige una contraseña de un solo uso. Al reiniciar aparece una pantalla azul (MOK): Enroll MOK > Continue > Yes, e ingresa esa contraseña. Sin esto el driver NVIDIA no carga."
  fi
  return 0
}

# Extension Manager: buscar, instalar y configurar extensiones de GNOME desde
# una app, sin pasar por el navegador ni extensions.gnome.org.
step_extensions() {
  rpm -q gnome-shell &>/dev/null || { skip "el escritorio no es GNOME"; return; }
  flatpaks com.mattjakeman.ExtensionManager
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
  firmwares=$(dnf repoquery -q --repo=rpmfusion-nonfree-tainted --qf '%{name}\n' '*-firmware' </dev/null 2>>"$LOG_FILE" | sort -u)
  [[ -n $firmwares ]] || { LAST_ERROR="no se pudo listar los firmwares de rpmfusion-nonfree-tainted"; return 1; }
  # shellcheck disable=SC2086  # una palabra por paquete
  pkgs $firmwares
}

step_hwaccel() {
  detect_gpus
  local done_any=0
  [[ -n $GPU_INFO ]] || { skip "no se detectó la GPU"; return; }
  ensure_rpmfusion || return 1
  if [[ $GPU_INFO == *Intel* ]]; then
    pkgs intel-media-driver || return 1
    done_any=1
  fi
  if [[ $GPU_INFO == *"AMD/ATI"* || $GPU_INFO == *Radeon* ]]; then
    # Los drivers de Fedora no traen H.264/H.265; los de RPM Fusion sí.
    pkgs --allowerasing mesa-va-drivers-freeworld || return 1
    done_any=1
  fi
  if [[ $GPU_INFO == *NVIDIA* ]]; then
    # VA-API sobre NVDEC: reproductores y navegadores decodifican con la GPU.
    pkgs libva-nvidia-driver || return 1
    done_any=1
  fi
  ((done_any)) || { skip "no hay GPU Intel, AMD ni NVIDIA que configurar"; return; }
}

step_fonts() {
  pkgs curl cabextract xorg-x11-font-utils fontconfig || return 1
  if ! rpm -q msttcore-fonts-installer &>/dev/null; then
    # El RPM no trae firma ni digest: se verifica con un sha256 fijo y se
    # instala con rpm (dnf lo rechaza; las dependencias ya las puso dnf).
    download "$MSFONTS_RPM" || return 1
    if [[ $(sha256sum "$DL" | cut -d' ' -f1) != "$MSFONTS_SHA256" ]]; then
      LAST_ERROR="el checksum de msttcore-fonts-installer no coincide"
      return 1
    fi
    local RUN_LABEL="instalando msttcore-fonts-installer (baja Arial, Calibri…)"
    run sudo rpm -i --nodigest --nosignature "$DL" ||
      { LAST_ERROR="msttcore-fonts-installer"; return 1; }
  fi
  # El RPM baja las fuentes en su instalación y no falla si la red se corta:
  # si faltan, se vuelven a bajar.
  if [[ ! -f /usr/share/fonts/msttcore/arial.ttf || ! -f /usr/share/fonts/msttcore/calibri.ttf ]]; then
    local RUN_LABEL="descargando fuentes de Microsoft"
    run sudo /usr/lib/msttcore-fonts-installer/refresh-msttcore-fonts.sh -F /usr/share/fonts/msttcore
    [[ -f /usr/share/fonts/msttcore/arial.ttf ]] || { LAST_ERROR="no se pudieron bajar las fuentes de Microsoft"; return 1; }
  fi
  install_cambria
}

# Cambria regular (msttcore 2.6 trae el resto de las fuentes de Office).
install_cambria() {
  local dest="$HOME/.local/share/fonts/microsoft" exe dir
  [[ -f $dest/CAMBRIA.TTC ]] && return 0
  download "$PPTVIEWER_URL" || return 1
  exe=$DL
  if [[ $(sha256sum "$exe" | cut -d' ' -f1) != "$PPTVIEWER_SHA256" ]]; then
    LAST_ERROR="el checksum de PowerPointViewer.exe no coincide"
    return 1
  fi
  dir=$(mktemp -d -p "$WORK_DIR") || return 1
  if ! run cabextract -q -d "$dir" -F ppviewer.cab "$exe" ||
    ! run cabextract -q -d "$dir" -F 'CAMBRIA.TTC' "$dir/ppviewer.cab" ||
    [[ ! -f $dir/CAMBRIA.TTC ]]; then
    LAST_ERROR="no se pudo extraer Cambria de PowerPointViewer.exe"
    return 1
  fi
  mkdir -p "$dest" && mv "$dir/CAMBRIA.TTC" "$dest/" && run fc-cache -f
}

step_compression() {
  # 7zip reemplazó a p7zip (que ya no existe desde Fedora 44).
  pkgs 7zip zstd pigz pbzip2
}

step_latex() {
  local fa=texlive-fontawesome6
  ((FEDORA_VERSION >= 44)) || fa=texlive-fontawesome5 # la 6 no existe en Fedora 43
  local RUN_LABEL="instalando TeX Live completo (varios GB)"
  pkgs texlive-scheme-full make google-roboto-fonts adobe-source-sans-pro-fonts "$fa"
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
  json=$(curl "${CURL_OPTS[@]}" https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>>"$LOG_FILE") ||
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
  if [[ -f $dest/$dir/proton ]]; then
    log "$dir ya está instalado."
    return 0
  fi
  download "$tar_url" || return 1
  tarball=$DL
  download "$sum_url" || return 1
  sums=$DL
  expected=$(cut -d' ' -f1 "$sums")
  if [[ $(sha512sum "$tarball" | cut -d' ' -f1) != "$expected" ]]; then
    LAST_ERROR="el checksum de $tag no coincide"
    return 1
  fi
  # Se extrae aparte y se mueve al final: un corte a mitad no deja una
  # carpeta incompleta que parezca instalada.
  local tmp RUN_LABEL="extrayendo $dir"
  if ! mkdir -p "$dest" || ! tmp=$(mktemp -d -p "$dest" .tmp-XXXXXX) ||
    ! run tar -xzf "$tarball" -C "$tmp" || ! rm -rf "${dest:?}/$dir" || ! mv "$tmp/$dir" "$dest/"; then
    [[ -n ${tmp:-} ]] && rm -rf "$tmp"
    LAST_ERROR="no se pudo extraer $tag"
    return 1
  fi
  rm -rf "$tmp"
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
    local f RUN_LABEL="instalando Oh My Zsh"
    download https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh || return 1
    f=$DL
    # --unattended: no cambia la shell ni abre zsh al terminar (eso colgaba
    # al script anterior).
    run env RUNZSH=no CHSH=no sh "$f" --unattended || { LAST_ERROR="instalador de Oh My Zsh"; return 1; }
  fi
  local custom="$HOME/.oh-my-zsh/custom"
  git_sync https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k" || return 1
  git_sync https://github.com/zsh-users/zsh-autosuggestions "$custom/plugins/zsh-autosuggestions" || return 1
  # Solo cambia los valores de fábrica de Oh My Zsh: si ya personalizaste el
  # tema o los plugins, se respetan. --follow-symlinks: no rompe dotfiles
  # enlazados (stow, chezmoi).
  if [[ -f $HOME/.zshrc ]]; then
    sed -i --follow-symlinks \
      -e 's|^ZSH_THEME="robbyrussell"$|ZSH_THEME="powerlevel10k/powerlevel10k"|' \
      -e 's|^plugins=(git)$|plugins=(git docker zsh-autosuggestions)|' "$HOME/.zshrc"
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
  local f RUN_LABEL="instalando Rust (rustup)"
  download https://sh.rustup.rs || return 1
  f=$DL
  # El PATH lo agrega el paso "env".
  run sh "$f" -y --no-modify-path
}

step_go() {
  local arch info latest file sha
  case $ARCH in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) skip "arquitectura $ARCH no soportada"; return ;;
  esac
  command -v python3 >/dev/null || pkgs python3 || return 1
  # Última versión estable, nombre del archivo y su sha256 desde go.dev.
  info=$(curl "${CURL_OPTS[@]}" 'https://go.dev/dl/?mode=json' 2>>"$LOG_FILE") ||
    { LAST_ERROR="no se pudo conectar con go.dev"; return 1; }
  info=$(python3 -c '
import json, sys
rel = json.load(sys.stdin)[0]
for f in rel["files"]:
    if f["os"] == "linux" and f["arch"] == sys.argv[1] and f["kind"] == "archive":
        print(rel["version"], f["filename"], f["sha256"])
        break
' "$arch" <<<"$info" 2>>"$LOG_FILE")
  read -r latest file sha <<<"$info"
  [[ ${latest:-} == go1.* && -n ${sha:-} ]] || { LAST_ERROR="respuesta inesperada de go.dev"; return 1; }
  if [[ -x /usr/local/go/bin/go && $(/usr/local/go/bin/go env GOVERSION 2>/dev/null) == "$latest" ]]; then
    log "$latest ya está instalado."
    return 0
  fi
  download "https://go.dev/dl/$file" || return 1
  [[ $(sha256sum "$DL" | cut -d' ' -f1) == "$sha" ]] || { LAST_ERROR="el checksum de $file no coincide"; return 1; }
  # Se extrae aparte y recién ahí se reemplaza: un archivo dañado no te deja sin Go.
  local RUN_LABEL="instalando $latest"
  if ! run sudo rm -rf /usr/local/go.new ||
    ! run sudo mkdir -p /usr/local/go.new ||
    ! run sudo tar -C /usr/local/go.new -xzf "$DL" ||
    ! run sudo rm -rf /usr/local/go ||
    ! run sudo mv /usr/local/go.new/go /usr/local/go ||
    ! run sudo rmdir /usr/local/go.new; then
    LAST_ERROR="no se pudo instalar $latest"
    return 1
  fi
}

step_node() {
  if [[ ! -s $HOME/.nvm/nvm.sh ]]; then
    local f RUN_LABEL="instalando NVM"
    download "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" || return 1
    f=$DL
    # PROFILE=/dev/null: no toca .bashrc/.zshrc; el paso "env" carga NVM.
    run env PROFILE=/dev/null bash "$f" || { LAST_ERROR="instalador de NVM"; return 1; }
  fi
  local RUN_LABEL="instalando Node.js LTS"
  # shellcheck disable=SC2016  # $HOME se expande dentro del bash hijo
  run bash -c 'source "$HOME/.nvm/nvm.sh" && nvm install --lts && nvm alias default "lts/*"'
}

step_uv() {
  if [[ -x $HOME/.local/bin/uv ]]; then
    run "$HOME/.local/bin/uv" self update
    return
  fi
  local f RUN_LABEL="instalando uv"
  download https://astral.sh/uv/install.sh || return 1
  f=$DL
  run env UV_NO_MODIFY_PATH=1 sh "$f"
}

step_docker() {
  local probe="https://download.docker.com/linux/fedora/$FEDORA_VERSION/$ARCH/stable/repodata/repomd.xml"
  if rpm -q docker-ce &>/dev/null || curl "${CURL_OPTS[@]}" -I -o /dev/null "$probe" 2>/dev/null; then
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
  local f RUN_LABEL="instalando Zed"
  download https://zed.dev/install.sh || return 1
  f=$DL
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
  local f RUN_LABEL="instalando Claude Code"
  download https://claude.ai/install.sh || return 1
  f=$DL
  run bash "$f"
}

step_opencode() {
  local f RUN_LABEL="instalando OpenCode"
  download https://opencode.ai/install || return 1
  f=$DL
  # --no-modify-path: el PATH lo pone el paso "env", no su propia línea en .bashrc.
  run bash "$f" --no-modify-path
}

step_herdr() {
  local f RUN_LABEL="instalando Herdr"
  download https://herdr.dev/install.sh || return 1
  f=$DL
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
    sed -i --follow-symlinks '/^# >>> fedora-postinstall >>>$/,/^# <<< fedora-postinstall <<<$/d' "$f" || return 1
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
                  (El paso "env" corre siempre, salvo con --skip env.)
  -h, --help      Muestra esta ayuda.
EOF
}

list_steps() {
  local s
  for s in "${STEPS[@]}"; do
    if [[ $s == @* ]]; then printf '\n%s\n' "${s#@}"; else printf '  %-12s %s\n' "${s%%|*}" "${s#*|}"; fi
  done
}

valid_ids() {
  local id s found
  for id in ${1//,/ }; do
    found=0
    for s in "${STEPS[@]}"; do [[ $s != @* && ${s%%|*} == "$id" ]] && found=1; done
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
  ui_step_stop
  if ((UI_LIVE)); then
    printf '\e[?25h' # vuelve a mostrar el cursor
    ((OSC_PROGRESS)) && printf '\e]9;4;0;0\a'
  fi
  for pid in "${BG_PIDS[@]}"; do kill "$pid" 2>/dev/null; done
  [[ -n $WORK_DIR ]] && rm -rf "$WORK_DIR"
}

on_interrupt() {
  trap '' INT TERM HUP
  # La señal puede llegar mientras corre un comando con la salida al log:
  # se vuelve a la terminal original antes de escribir nada.
  exec 1>&3 2>&4
  ui_step_stop
  [[ -n $CURRENT_STEP ]] && ui_result "■" "$C_YELLOW" "$CURRENT_STEP" "interrumpido"
  printf '\n  %s■ Instalación interrumpida.%s Lo que alcanzó a instalarse se mantiene;\n' "$C_YELLOW" "$C_RESET"
  printf '    vuelve a ejecutar el comando para completar el resto.\n'
  # Que lo ya instalado funcione: PATH en .bashrc/.zshrc y snapshots de dnf.
  step_env >/dev/null 2>&1
  install_snapper_hook >/dev/null 2>&1
  summary
  exit 130
}

# Comprobaciones que no necesitan sudo: se hacen antes de mostrar nada.
preflight() {
  [[ $EUID -ne 0 ]] || die "No lo ejecutes como root ni con sudo: ejecútalo con tu usuario; pedirá sudo cuando haga falta."
  local distro ps
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

  if ! mkdir -p "$LOG_DIR" || ! : >"$LOG_FILE"; then
    die "No se pudo crear el log en $LOG_FILE"
  fi
  ln -sfn "$LOG_FILE" "$LOG_DIR/latest.log"
  # En el disco y no en /tmp (que está en RAM): GE-Proton pesa más de 500 MB.
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
  WORK_DIR=$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}" fedora-postinstall.XXXXXX) ||
    die "No se pudo crear un directorio temporal."
  STATUS_FILE="$WORK_DIR/status"
  exec 3>&1 4>&2 # copia de la terminal, para on_interrupt
  trap cleanup EXIT
  trap on_interrupt INT TERM HUP

  # ¿Notebook con batería y sin cargador?
  for ps in /sys/class/power_supply/*; do
    [[ $(cat "$ps/type" 2>/dev/null) == Battery ]] && ON_BATTERY=1
  done
  for ps in /sys/class/power_supply/*; do
    [[ $(cat "$ps/type" 2>/dev/null) == Mains && $(cat "$ps/online" 2>/dev/null) == 1 ]] && ON_BATTERY=0
  done
  return 0
}

acquire_sudo() {
  if ! command sudo -n true 2>/dev/null; then
    say ""
    say "  Se necesita tu contraseña de sudo ${C_DIM}(solo esta vez; después no se pregunta nada)${C_RESET}:"
  fi
  command sudo -v || die "No se pudo obtener permisos de sudo."
  # Mantiene sudo activo mientras dure la instalación (puede tardar bastante).
  (while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done) >/dev/null 2>&1 &
  BG_PIDS+=("$!")
  # Desde aquí sudo nunca pregunta: si la sesión venciera, el comando falla
  # con un error en vez de quedarse esperando una contraseña invisible.
  sudo() { command sudo -n "$@"; }
  # Evita que el equipo se suspenda (también al cerrar la tapa) a mitad de la instalación.
  if command -v systemd-inhibit >/dev/null; then
    systemd-inhibit --what=idle:sleep:handle-lid-switch --who=fedora-postinstall --why="Instalando paquetes" \
      sleep infinity >/dev/null 2>&1 &
    BG_PIDS+=("$!")
  fi
}

run_step() {
  local id=$1 desc=$2 rc start=$EPOCHSECONDS
  STEP_NUM=$((STEP_NUM + 1))
  SKIP_REASON="" LAST_ERROR="" LAST_CMD=""
  log ""
  log "===== [$id] $desc ====="
  STEP_OFFSET[$id]=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
  CURRENT_STEP=$desc
  ui_step_start "$desc"
  "step_$id"
  rc=$?
  CURRENT_STEP=""
  ui_step_stop
  case $rc in
    0)
      ui_result "✓" "$C_GREEN" "$desc" "$(fmt_time $((EPOCHSECONDS - start)))"
      OK+=("$id")
      ;;
    99)
      ui_result "–" "$C_DIM" "$desc" "$SKIP_REASON"
      SKIPPED+=("$desc: $SKIP_REASON")
      ;;
    *)
      [[ -n $LAST_ERROR ]] || LAST_ERROR="falló: ${LAST_CMD:-revisa el log}"
      ui_result "✗" "$C_RED" "$desc" "$LAST_ERROR"
      FAILED+=("$desc — $LAST_ERROR")
      FAILED_IDS+=("$id")
      log "!! Paso '$id' falló (código $rc)"
      ;;
  esac
}

# Imprime un texto largo cortado por palabras, con sangría en las líneas siguientes.
say_wrapped() {
  local prefix=$1 indent=$2 text=$3 width first=1 line
  width=$(($(ui_cols) - ${#indent} - 2))
  while IFS= read -r line; do
    if ((first)); then say "${prefix}${line}"; first=0; else say "${indent}${line}"; fi
  done < <(fold -s -w "$width" <<<"$text" | sed 's/ *$//')
}

summary() {
  local item ids cols width elapsed errors pending
  cols=$(ui_cols)
  width=$((cols - 4))
  elapsed=$(fmt_time $((EPOCHSECONDS - RUN_START)))
  ((UI_LIVE)) && printf '\e]0;Fedora PostInstall · listo\a'
  say ""
  say "  ${C_ACCENT}$(repeat '─' "$width")${C_RESET}"
  pending=$((STEP_TOTAL - ${#OK[@]} - ${#FAILED[@]} - ${#SKIPPED[@]}))
  if ((pending > 0)); then
    say "  ${C_BOLD}${C_YELLOW}Instalación incompleta${C_RESET} ${C_DIM}en $elapsed · faltaron $pending pasos${C_RESET}"
    ((UI_LIVE)) && printf '\e]0;Fedora PostInstall · interrumpido\a'
  elif ((${#FAILED[@]})); then
    say "  ${C_BOLD}Instalación terminada con errores${C_RESET} ${C_DIM}en $elapsed${C_RESET}"
    ((UI_LIVE)) && printf '\e]0;Fedora PostInstall · con errores\a'
  else
    say "  ${C_BOLD}${C_GREEN}Instalación completa${C_RESET} ${C_DIM}en $elapsed${C_RESET}"
  fi
  if ((${#FAILED[@]})); then
    errors="${C_RED}✗ ${#FAILED[@]} con error$( ((${#FAILED[@]} == 1)) || echo es)${C_RESET}"
  else
    errors="${C_DIM}✗ 0 con errores${C_RESET}"
  fi
  say "  ${C_GREEN}✓ ${#OK[@]} listo$( ((${#OK[@]} == 1)) || echo s)${C_RESET}   $errors   ${C_DIM}– ${#SKIPPED[@]} omitido$( ((${#SKIPPED[@]} == 1)) || echo s)${C_RESET}"
  if ((${#FAILED[@]})); then
    say ""
    say "  ${C_BOLD}Con errores${C_RESET}"
    local i excerpt line
    for i in "${!FAILED[@]}"; do
      say_wrapped "    ${C_RED}✗${C_RESET} " "      " "${FAILED[$i]}"
      # Las líneas del log de ese paso que explican el error.
      excerpt=$(tail -c +$((${STEP_OFFSET[${FAILED_IDS[$i]}]:-0} + 1)) "$LOG_FILE" 2>/dev/null |
        awk 'NR > 1 && /^===== \[/ {exit} {print}' |
        grep -E 'Problem|No match|nothing provides|conflicts|[Ee]rror|[Ff]ailed|404' | grep -v '^!!' |
        awk '!seen[$0]++' | tail -n 3)
      while IFS= read -r line; do
        [[ -n $line ]] && say "      ${C_DIM}$(trunc "${line#"${line%%[![:space:]]*}"}" $((cols - 10)))${C_RESET}"
      done <<<"$excerpt"
    done
    ids=$(IFS=,; printf '%s' "${FAILED_IDS[*]}")
    say "    ${C_DIM}Para reintentar solo eso:${C_RESET}"
    say "    curl -fsSL $REPO_RAW | bash -s -- --only $ids"
  fi
  if ((${#NOTES[@]})); then
    say ""
    say "  ${C_BOLD}Pendiente${C_RESET}"
    for item in "${NOTES[@]}"; do say_wrapped "    ${C_YELLOW}•${C_RESET} " "      " "$item"; done
  fi
  say ""
  say "  ${C_DIM}Log completo: ${LOG_FILE/#$HOME/\~}${C_RESET}"
  say ""
  # Aviso de que terminó, por si la ventana quedó atrás.
  if ((UI_LIVE)); then
    printf '\a'
    if command -v notify-send >/dev/null && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
      notify-send -a "Fedora PostInstall" "Fedora PostInstall" \
        "Terminó: ${#OK[@]} listos, ${#FAILED[@]} con errores." 2>/dev/null || true
    fi
  fi
}

main() {
  parse_args "$@"
  preflight

  local s id group="" count=0
  for s in "${STEPS[@]}"; do
    [[ $s == @* ]] && continue
    selected "${s%%|*}" && count=$((count + 1))
  done
  STEP_TOTAL=$count
  RUN_START=$EPOCHSECONDS

  ui_banner
  acquire_sudo
  if ((FEDORA_VERSION > MAX_TESTED_FEDORA)); then
    say "  ${C_YELLOW}Aviso:${C_RESET} Fedora $FEDORA_VERSION todavía no está probada con este script; sigo igual."
  fi
  say "  ${C_DIM}$STEP_TOTAL pasos · se puede volver a ejecutar sin problema${C_RESET}"
  say "  ${C_DIM}Detalle en vivo desde otra terminal: tail -f ${LOG_DIR/#$HOME/\~}/latest.log${C_RESET}"
  ((UI_LIVE)) && printf '\e[?25l' # oculta el cursor mientras dibuja

  for s in "${STEPS[@]}"; do
    if [[ $s == @* ]]; then
      group=${s#@}
      continue
    fi
    id=${s%%|*}
    selected "$id" || continue
    if [[ -n $group ]]; then
      say ""
      say "  ${C_BOLD}${C_ACCENT}${group}${C_RESET}"
      group=""
    fi
    run_step "$id" "${s#*|}"
  done

  install_snapper_hook
  summary
  ((${#FAILED[@]} == 0))
}

main "$@"
