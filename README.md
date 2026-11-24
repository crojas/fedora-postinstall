# Fedora PostInstall

Suite de instalación que deja **Fedora Workstation** optimizado y listo justo después de instalarlo: desarrollo con agentes de IA, edición de foto y video, grabación y gaming. Un solo comando, sin preguntas.

```bash
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash
```

Si prefieres revisar el script antes de ejecutarlo:

```bash
curl -fsSLO https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh
less install.sh
bash install.sh
```

- **Ejecútalo con tu usuario**, no con `sudo`. Pide la contraseña de sudo una sola vez, al principio.
- **No pregunta nada.** Muestra el avance en vivo (paso actual, paquete que está instalando, barra de progreso general) y, si un paso falla, sigue con el resto. Al final verás un resumen con lo que funcionó, lo que falló y por qué, y lo que queda pendiente.
- **Lo puedes ejecutar las veces que quieras.** Lo que ya está instalado lo deja igual o lo actualiza. Si lo cortas con Ctrl-C, vuelve a ejecutarlo para completar el resto.
- **Todo queda en un log:** `~/.local/state/fedora-postinstall/`. Para seguirlo en vivo desde otra terminal: `tail -f ~/.local/state/fedora-postinstall/latest.log`.

**Requisitos:**

- Fedora Workstation 43, 44 o 45 (las últimas tres versiones), x86_64 o ARM (aarch64), con internet.
- Unos 25 GB libres. LaTeX completo y Steam son lo más pesado; el tiempo depende sobre todo de tu conexión.
- No sirve para las ediciones Atomic (Silverblue, Kinoite).
- En ARM se omiten Chrome, Steam y GE-Proton, porque no existen para esa arquitectura.
- En un notebook, déjalo enchufado: con batería no actualiza el firmware.

## Qué hace y por qué

### Sistema

| Paso | Qué hace | Por qué |
|---|---|---|
| `dnf` | Descargas en paralelo, mirror más rápido, guarda 3 kernels | Instalar y actualizar es mucho más rápido, y si un kernel nuevo falla tienes dos anteriores para arrancar |
| `snapshots` | Guarda un snapshot de `/` antes de empezar y, desde ahí, uno antes y otro después de cada `dnf` (snapper + Btrfs Assistant) | Si un update rompe algo, vuelves al estado anterior. Ver [Volver atrás](#volver-atrás) |
| `upgrade` | Actualiza todo el sistema | Partir con todo al día |
| `limits` | Sube los límites de inotify | Editores, dev servers y agentes vigilan archivos. Con varios a la vez se pasa el límite de 128 y el hot-reload deja de funcionar sin avisar |
| `repos` | RPM Fusion (verificando su firma), Flathub y OpenH264 | Ahí están los codecs, Steam, los drivers NVIDIA y las apps Flatpak |
| `firmware` | Actualiza firmware vía LVFS | BIOS, SSD y periféricos con sus parches de seguridad y estabilidad |

### Hardware

| Paso | Qué hace | Por qué |
|---|---|---|
| `nvidia` | Driver NVIDIA, solo si detecta una GPU NVIDIA. Elige la serie correcta para GPU antiguas y prepara la llave de Secure Boot | El driver libre no sirve para jugar ni para NVENC/CUDA. Con Secure Boot, sin la llave el driver no carga |
| `hwaccel` | Drivers VA-API completos para Intel, AMD y NVIDIA | Los de Fedora no aceleran H.264/H.265; con estos, el video y la edición usan la GPU y no la CPU |

### Escritorio

| Paso | Qué hace | Por qué |
|---|---|---|
| `extensions` | Extension Manager (solo en GNOME) | Buscar, instalar y configurar extensiones de GNOME desde una app, sin pasar por el navegador |

### Multimedia y apps

| Paso | Qué hace | Por qué |
|---|---|---|
| `multimedia` | FFmpeg completo, codecs, DVD, firmwares extra | Fedora trae solo codecs libres, así que muchos videos no se ven ni se pueden editar |
| `fonts` | Fuentes de Microsoft (Arial, Calibri, Cambria…), verificadas con checksum | Para que los documentos de Office y las webs se vean como deben |
| `compression` | 7zip, zstd, pigz, pbzip2 | Abrir cualquier formato y comprimir usando todos los núcleos |
| `chrome`, `brave` | Navegadores | — |
| `apps` | VLC, GIMP, OBS Studio + captura de juegos, Shotcut | Ver, editar y grabar. El plugin de OBS captura los juegos directo desde Vulkan, sin la latencia de grabar la pantalla |
| `office` | ONLYOFFICE | Abre bien los .docx, .xlsx y .pptx |

### Gaming

| Paso | Qué hace | Por qué |
|---|---|---|
| `gaming` | Steam, Gamescope, GameMode, MangoHud, ProtonUp-Qt | GameMode da prioridad al juego y sube el rendimiento de la CPU, MangoHud muestra FPS y temperaturas, Gamescope limita FPS y escala con FSR |
| `ntsync` | Deja cargado el módulo NTSYNC | Imita la sincronización de Windows en el kernel. GE-Proton lo aprovecha y en varios juegos mejora bastante los FPS |
| `protonge` | Baja la última versión de GE-Proton (verificada con su checksum) | Trae más arreglos que el Proton oficial y es la versión que usa NTSYNC |

### Desarrollo

| Paso | Qué hace | Por qué |
|---|---|---|
| `devtools` | Compiladores (gcc, clang, cmake) y librerías de desarrollo | Para compilar dependencias nativas de Python, Ruby, Node, etc. |
| `cli` | gh, ripgrep, fd, fzf, jq, delta, lazygit, direnv, distrobox | Las herramientas que más usan los agentes, diffs legibles, variables por proyecto y contenedores para aislar cosas |
| `zsh` | Zsh + Oh My Zsh + Powerlevel10k + autosuggestions, como shell por defecto | Terminal más cómoda: sugerencias, git en el prompt. Si ya personalizaste tu tema o plugins, se respetan |
| `env` | Un solo bloque en `.bashrc` y `.zshrc` con el PATH, NVM, direnv y fzf (Ctrl-R) | Que todo lo que se instala en tu carpeta personal funcione al abrir la terminal |
| `ghostty` | Terminal Ghostty | Terminal rápida, con aceleración por GPU |
| `rust`, `go`, `node`, `uv` | rustup, Go (última versión, verificada con checksum), Node.js LTS con NVM, uv para Python | Los lenguajes quedan en tu carpeta personal, sin conflictos con los paquetes del sistema |
| `docker` | Docker Engine + Compose, con tu usuario en el grupo `docker` | Para usar `docker` sin `sudo`. Si Docker aún no publica paquetes para una Fedora nueva, usa el de Fedora |
| `zed`, `cursor`, `dbeaver` | Editores y cliente de bases de datos | — |
| `claude`, `opencode`, `herdr` | Claude Code, OpenCode y Herdr | Agentes de IA para programar, y Herdr para correr varios en paralelo |
| `obsidian` | Obsidian | Notas y documentación en Markdown |

### Documentos

| Paso | Qué hace | Por qué |
|---|---|---|
| `latex` | TeX Live completo | Documentos y CV en LaTeX sin instalar paquetes sueltos. Va al final porque es lo más pesado: todo lo demás ya queda usable antes |

### Lo que no toca, porque Fedora ya lo trae

zram (swap comprimida en RAM), compresión `zstd` en Btrfs, `vm.max_map_count` alto para juegos y el TRIM semanal del SSD. Varias guías para optimizar Linux lo recomiendan, pero en Fedora ya viene configurado.

## Opciones

```bash
# Ver todos los pasos
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --list

# Todo menos LaTeX
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --skip latex

# Solo algunos pasos (el paso env corre siempre, salvo con --skip env)
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --only docker,node
```

Si algo falla, el resumen final muestra el motivo, las líneas del log que lo explican y el comando exacto para reintentar solo eso.

## Después de instalar

1. **Reinicia** si el resumen lo pide (kernel nuevo, firmware o drivers NVIDIA). Si se actualiza el firmware, al reiniciar puede tardar unos minutos: no apagues el equipo.
2. **NVIDIA con Secure Boot:** *antes* de reiniciar, ejecuta el comando `mokutil` que indica el resumen y elige una contraseña. Al reiniciar aparece una pantalla azul: *Enroll MOK* → *Continue* → *Yes*, e ingresa esa contraseña.
3. **Cierra sesión y vuelve a entrar** para usar zsh y Docker sin `sudo`. La primera vez que abras la terminal, Powerlevel10k te ofrece configurar el prompt.
4. **Steam:** en Propiedades del juego → Compatibilidad, elige GE-Proton. Opciones de lanzamiento útiles en [docs/gaming.md](docs/gaming.md#opciones-de-lanzamiento-en-steam).

### Volver atrás

Si `/` está en Btrfs, el script guarda un snapshot llamado *antes de fedora-postinstall*, y después uno antes y otro después de cada `dnf`.

- **Con interfaz gráfica:** abre Btrfs Assistant → *Snapper*, elige el snapshot y restaura.
- **Desde una terminal** (también sirve en una consola de texto con Ctrl+Alt+F3): `sudo snapper list` para ver los números y `sudo snapper undochange <n>..0` para deshacer todo lo que cambió desde el snapshot `<n>`.

**Qué no cubre:**

- `/home` no se toca. `/var` sí vuelve atrás, incluidos los volúmenes de Docker y las apps Flatpak del sistema.
- `/boot` no entra en el snapshot. Si el problema vino con un kernel nuevo, elige el kernel anterior en el menú de inicio.

## Qué cambia en tu sistema

Para que sepas qué toca el script antes de ejecutarlo:

- **Repositorios:** RPM Fusion (free, nonfree y tainted), Flathub, OpenH264, Google Chrome, Brave, Docker, Cursor y el COPR de Ghostty.
- **Configuración y servicios:**
  - ajustes de DNF (`dnf config-manager setopt`), `/etc/sysctl.d/90-fedora-postinstall.conf` y `/etc/modules-load.d/ntsync.conf`;
  - snapper (`/etc/snapper/configs/root`, `snapper-cleanup.timer` y `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions`);
  - el servicio `docker` habilitado;
  - Go en `/usr/local/go`;
  - el firmware del equipo, si hay actualizaciones.
- **Tu usuario:** queda con zsh como shell y en el grupo `docker`.
- **Tu carpeta personal:**
  - `~/.oh-my-zsh`, `~/.nvm`, `~/.cargo`, `~/.rustup` y `~/.local/bin` (uv, Zed, Claude Code, Herdr);
  - `~/.opencode`, `~/.local/share/fonts/microsoft`, GE-Proton en `~/.local/share/Steam/compatibilitytools.d` y los logs;
  - un bloque marcado `# >>> fedora-postinstall >>>` en `.bashrc` y `.zshrc`, que se reescribe en cada ejecución y nunca se duplica;
  - `delta` como visor de diffs en git, solo si no tenías otro configurado.

### Seguridad

- **Verificado:**
  - El paquete de RPM Fusion se verifica con las llaves que publica Fedora.
  - Go, GE-Proton y las fuentes de Microsoft se verifican con checksum. El RPM de las fuentes no viene firmado, por eso se fija su sha256 en el script.
- **Sin versión fija:** los instaladores oficiales (rustup, uv, NVM, Oh My Zsh, Zed, Claude Code, OpenCode, Herdr) se descargan por HTTPS desde sus sitios y se usa siempre su última versión.
- **Grupo `docker`:** estar en él equivale a tener permisos de root. Tenlo en cuenta si dejas agentes corriendo con permisos amplios.

## Paso a paso manual

Si prefieres hacerlo a mano o ver los comandos exactos:

- [docs/sistema.md](docs/sistema.md): sistema, snapshots, codecs, drivers, fuentes y apps
- [docs/gaming.md](docs/gaming.md): Steam, NTSYNC, GE-Proton y grabación
- [docs/development.md](docs/development.md): herramientas, lenguajes, Docker y editores
