# Fedora PostInstall

Suite de instalación para dejar **Fedora Workstation** tuneado al tiro después de instalarlo: desarrollo con agentes de IA, edición de foto y video, grabación y gaming. Un comando, cero preguntas.

```bash
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash
```

- **Córrelo con tu usuario**, no con `sudo`. Te pide la clave de sudo una sola vez al principio.
- **No pregunta nada.** Si un paso falla, sigue con el resto y al final te muestra un resumen con lo que funcionó, lo que falló y lo que queda pendiente (reiniciar, cerrar sesión…).
- **Lo puedes correr las veces que quieras.** Lo que ya está instalado lo deja igual o lo actualiza.
- **Todo queda en un log:** `~/fedora-postinstall-<fecha>.log`. Para seguirlo en vivo: `tail -f ~/fedora-postinstall-*.log`.

**Requisitos:** Fedora Workstation 43, 44 o 45 (las últimas tres versiones), x86_64 o ARM (aarch64) e internet. No sirve para las ediciones Atomic (Silverblue, Kinoite). En ARM se saltan Chrome, Steam y GE-Proton porque no existen para esa arquitectura.

## Qué hace y por qué

### Sistema

| Paso | Qué hace | Por qué |
|---|---|---|
| `dnf` | Descargas en paralelo, mirror más rápido, guarda solo 2 kernels | Instalar y actualizar se hace bastante más rápido |
| `snapshots` | Saca un snapshot de `/` antes y después de cada `dnf` (snapper + Btrfs Assistant) | Si un update rompe algo, por ejemplo el driver NVIDIA con un kernel nuevo, vuelves al estado anterior en dos clics. Tus archivos de `/home` no se tocan |
| `upgrade` | Actualiza todo el sistema | Partir con todo al día |
| `limits` | Sube los límites de inotify | Editores, dev servers y agentes vigilan archivos. Con varios a la vez se pasa el límite de 128 y el hot-reload deja de funcionar sin avisar |
| `repos` | RPM Fusion, Flathub y OpenH264 | Ahí están los codecs, Steam, los drivers NVIDIA y las apps Flatpak |
| `firmware` | Actualiza firmware vía LVFS | BIOS, SSD y periféricos con sus parches de seguridad y estabilidad |

### Hardware

| Paso | Qué hace | Por qué |
|---|---|---|
| `nvidia` | Driver NVIDIA (solo si detecta una GPU NVIDIA) | El driver libre no sirve para jugar ni para usar NVENC o CUDA |
| `hwaccel` | Drivers VA-API completos para Intel y AMD | Los de Fedora no aceleran H.264/H.265. Con estos, el video y la edición usan la GPU y no la CPU |

### Multimedia, edición y apps

| Paso | Qué hace | Por qué |
|---|---|---|
| `multimedia` | FFmpeg completo, codecs, DVD, firmwares extra | Fedora trae solo codecs libres, así que muchos videos no se ven ni se pueden editar |
| `fonts` | Fuentes de Microsoft (Arial, Calibri, Cambria…) | Para que los documentos de Office y las webs se vean como deben |
| `compression` | 7zip, zstd, pigz, pbzip2 | Abrir cualquier formato y comprimir usando todos los núcleos |
| `latex` | TeX Live completo | Documentos y CV en LaTeX sin andar instalando paquetes a medias |
| `chrome`, `brave` | Navegadores | — |
| `apps` | VLC, GIMP, OBS Studio + captura de juegos, Shotcut | Ver, editar y grabar. El plugin de OBS captura los juegos directo desde Vulkan, sin la latencia de grabar la pantalla |
| `office` | ONLYOFFICE | Abre bien los .docx, .xlsx y .pptx |

### Gaming

| Paso | Qué hace | Por qué |
|---|---|---|
| `gaming` | Steam, Gamescope, GameMode, MangoHud, ProtonUp-Qt | GameMode exprime la CPU mientras juegas, MangoHud muestra FPS y temperaturas, Gamescope limita FPS y escala con FSR |
| `ntsync` | Deja cargado el módulo NTSYNC | Imita la sincronización de Windows en el kernel. GE-Proton lo aprovecha y en varios juegos sube harto los FPS |
| `protonge` | Baja la última versión de GE-Proton (verificada con su checksum) | Trae más arreglos que el Proton oficial y es la que usa NTSYNC |

### Desarrollo

| Paso | Qué hace | Por qué |
|---|---|---|
| `devtools` | Compiladores (gcc, clang, cmake) y librerías de desarrollo | Para compilar dependencias nativas de Python, Ruby, Node, etc. |
| `cli` | gh, ripgrep, fd, fzf, jq, delta, lazygit, direnv, distrobox | Las herramientas que más usan los agentes, más diffs legibles, variables por proyecto y contenedores para aislar cosas |
| `zsh` | Zsh + Oh My Zsh + Powerlevel10k + autosuggestions, como shell por defecto | Terminal más cómoda: sugerencias, git en el prompt |
| `ghostty` | Terminal Ghostty | Terminal rápida, con aceleración por GPU |
| `rust`, `go`, `node`, `uv` | rustup, Go (última versión), Node.js LTS con NVM, uv para Python | Los lenguajes instalados en tu home, sin pelear con los paquetes del sistema |
| `docker` | Docker Engine + Compose, con tu usuario en el grupo `docker` | Para usar `docker` sin `sudo`. Si Docker aún no publica paquetes para una Fedora nueva, usa el de Fedora |
| `zed`, `cursor`, `dbeaver` | Editores y cliente de bases de datos | — |
| `claude`, `opencode`, `herdr` | Claude Code, OpenCode y Herdr | Agentes de IA para programar, y Herdr para correr varios en paralelo |
| `obsidian` | Obsidian | Notas y documentación en Markdown |
| `env` | Un solo bloque en `.bashrc` y `.zshrc` con el PATH, NVM, direnv y fzf (Ctrl-R) | Que todo lo anterior funcione al abrir la terminal |

### Lo que no toca, porque Fedora ya lo trae

zram (swap comprimida en RAM), compresión `zstd` en Btrfs, `vm.max_map_count` alto para juegos y el TRIM semanal del SSD. Varias guías de "tunear Linux" lo recomiendan, pero en Fedora ya viene listo.

## Opciones

```bash
# Ver todos los pasos
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --list

# Todo menos LaTeX (pesa varios GB)
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --skip latex

# Solo algunos pasos
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --only docker,node
```

Si algo falla, el resumen final te da el comando exacto para reintentar solo eso.

## Después de instalar

1. **Reinicia** (kernel nuevo, firmware o drivers NVIDIA).
2. **NVIDIA con Secure Boot:** el resumen te dice cómo registrar la llave para que cargue el driver.
3. **Steam:** en Propiedades del juego → Compatibilidad, elige GE-Proton. Opciones de lanzamiento útiles:
   - `gamemoderun %command%`: modo rendimiento
   - `mangohud %command%`: FPS en pantalla
   - `obs-gamecapture %command%`: para grabar el juego con OBS
4. **Si un update rompe algo:** abre Btrfs Assistant → Snapper, elige el snapshot de antes y restaura.
5. La primera vez que abras la terminal, Powerlevel10k te ofrece configurar el prompt.

## Qué cambia en tu sistema

Para que sepas qué toca el script antes de correrlo:

- **Repos nuevos:** RPM Fusion, Flathub, Brave, Docker, Cursor y el COPR de Ghostty.
- **Configuración del sistema:** ajustes de DNF (`dnf config-manager setopt`), `/etc/sysctl.d/90-fedora-postinstall.conf`, `/etc/modules-load.d/ntsync.conf` y `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions`.
- **Tu usuario:** queda con zsh como shell y en el grupo `docker`.
- **Tu home:** un bloque marcado `# >>> fedora-postinstall >>>` en `.bashrc` y `.zshrc` (se reescribe en cada ejecución, nunca se duplica) y `delta` como visor de diffs en git, solo si no tenías otro configurado.

## Paso a paso manual

Si prefieres hacerlo a mano o ver los comandos exactos:

- [docs/sistema.md](docs/sistema.md): sistema, codecs, fuentes y apps
- [docs/gaming.md](docs/gaming.md): Steam, NTSYNC, GE-Proton y grabación
- [docs/development.md](docs/development.md): herramientas, lenguajes, Docker y editores
