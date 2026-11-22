# Fedora PostInstall

Script de postinstalación para **Fedora Workstation 43, 44 y 45** orientado a desarrollo, edición de foto/video y gaming. Lo corres una vez después de instalar Fedora y deja el equipo listo, sin preguntas.

## Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash
```

- Córrelo con tu usuario (no con `sudo`): pide la contraseña de sudo **una sola vez** al inicio.
- No hace preguntas: instala todo y al final muestra un resumen con lo que funcionó, lo que falló y lo que queda pendiente (reiniciar, cerrar sesión…).
- Se puede volver a ejecutar sin problema: lo que ya está instalado lo deja igual o lo actualiza.
- Todo el detalle queda en `~/fedora-postinstall-<fecha>.log`. Para verlo en vivo desde otra terminal: `tail -f ~/fedora-postinstall-*.log`.

### Qué instala

| Paso | Qué hace |
|---|---|
| `dnf` | Optimiza DNF (descargas en paralelo, mirror más rápido, etc.) |
| `upgrade` | Actualiza el sistema |
| `repos` | RPM Fusion (free, nonfree, tainted), Flathub y OpenH264 |
| `firmware` | Firmware vía LVFS (`fwupdmgr`) |
| `nvidia` | Drivers NVIDIA (solo si detecta una GPU NVIDIA) |
| `multimedia` | FFmpeg completo, codecs, DVD y firmwares adicionales |
| `hwaccel` | Aceleración de video por hardware para Intel/AMD |
| `fonts` | Fuentes de Microsoft (Core Fonts + Cambria) |
| `compression` | 7zip, zstd, pigz, pbzip2 |
| `latex` | TeX Live completo + fuentes |
| `chrome`, `brave` | Navegadores |
| `apps` | VLC, GIMP, OBS Studio, Shotcut |
| `office` | ONLYOFFICE y Obsidian (Flatpak) |
| `gaming` | Steam, GameMode, MangoHud, GOverlay y ProtonUp-Qt |
| `devtools` | Compiladores y librerías de desarrollo |
| `zsh` | Zsh + Oh My Zsh + Powerlevel10k + autosuggestions, como shell por defecto |
| `ghostty` | Terminal Ghostty |
| `rust`, `go`, `node`, `uv` | Rust (rustup), Go (última versión), Node.js LTS (NVM), uv (Python) |
| `docker` | Docker Engine + Compose, con tu usuario en el grupo `docker` |
| `zed`, `cursor`, `dbeaver` | Editores |
| `claude`, `opencode` | CLIs de IA |
| `env` | Agrega al PATH todo lo anterior en `.bashrc` y `.zshrc` |

### Opciones

```bash
# Ver los pasos disponibles
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --list

# Todo menos LaTeX
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --skip latex

# Solo algunos pasos
curl -fsSL https://raw.githubusercontent.com/crojas/fedora-postinstall/main/install.sh | bash -s -- --only docker,node
```

Si algún paso falla, el resumen final muestra el comando exacto para reintentar solo esos pasos.

### Después de instalar

1. Reinicia el equipo (kernel nuevo, firmware o drivers NVIDIA).
2. Con **Secure Boot** activo y GPU NVIDIA, el resumen te indica cómo registrar la llave de `akmods` para que el driver cargue.
3. Al abrir la terminal por primera vez, Powerlevel10k te ofrecerá configurar el prompt.

## Instalación manual

Los mismos pasos, explicados uno a uno, por si quieres hacerlos a mano.

## Índice

- [Optimización del Sistema](#mejorar-el-comportamiento-del-gestor-de-paquetes)
- [Repositorios](#agregar-repositorios-rpmfusion)
- [Firmware](#actualizar-firmware-de-hardware-via-lvfs)
- [Drivers NVIDIA](#instalar-drivers-de-nvidia)
- [Multimedia](#instalar-codecs-multimedia)
- [Fuentes](#fuentes-de-windows)
- [Aplicaciones](#instalar-apps)
- [Gaming](#gaming)
- [Desarrollo](#desarrollo)

# Mejorar el comportamiento del gestor de paquetes.

```
sudo nano /etc/dnf/dnf.conf
```

### Editar el fichero y agrear lo siguiente

```
[main]
fastestmirror=True
max_parallel_downloads=20
gpgcheck=True
installonly_limit=2
clean_requirements_on_remove=True
best=False
skip_if_unavailable=True
keepcache=False
```

- **`fastestmirror=True`**
  Activa la búsqueda automática del espejo (mirror) más rápido disponible, acelerando las descargas de paquetes.
- **`max_parallel_downloads=20`**
  Permite hasta 20 descargas de paquetes en paralelo, lo que mejora significativamente la velocidad de instalación y actualización.
- **`gpgcheck=True`**
  Verifica la firma GPG de los paquetes antes de instalarlos, garantizando su autenticidad y seguridad.
- **`installonly_limit=2`**
  Mantiene un máximo de 2versiones del mismo kernel (u otros paquetes `installonly`). Cuando se instala uno nuevo, elimina los más antiguos si se supera el límite.
- **`clean_requirements_on_remove=True`**
  Al desinstalar un paquete, también elimina automáticamente las dependencias que ya no se utilizan, ayudando a mantener el sistema limpio.
- **`best=False`**
  Permite instalar paquetes aunque no esté disponible la última versión. Esto evita errores o bloqueos si no se encuentra la versión más reciente en los repositorios.
- **`skip_if_unavailable=True`**
  Si un repositorio no está disponible temporalmente, lo ignora y continúa con los otros disponibles, evitando que falle todo el proceso de instalación o actualización.
- **`keepcache=False`**
  Elimina automáticamente los archivos `.rpm` descargados una vez instalados. Ayuda a ahorrar espacio en disco.

# Agregar repositorios [RPMFusion](rpmfusion.org)

```
sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

# Actualizar firmware de hardware via [LVFS](https://fwupd.org/)

```
sudo fwupdmgr refresh --force
sudo fwupdmgr get-devices
sudo fwupdmgr get-updates
sudo fwupdmgr update
```

Luego hacer reboot.

# Instalar drivers de NVIDIA

```
sudo dnf upgrade --refresh
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
```

Luego hacer reboot.

# Instalar codecs multimedia

## Cambiar a la version completa de ffmpeg

```
sudo dnf swap ffmpeg-free ffmpeg --allowerasing
```

## Instalar codecs

```
sudo dnf update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf group install -y sound-and-video
```

## Para ejecutar DVD

```
sudo dnf install rpmfusion-free-release-tainted
sudo dnf install libdvdcss
```

## Firmwares adicionales

```
sudo dnf install rpmfusion-nonfree-release-tainted
sudo dnf --repo=rpmfusion-nonfree-tainted install "*-firmware"
```

## Librerías para reproducción de video, aceleración por hardware y codificación.

```
sudo dnf install ffmpeg-libs libva libva-utils
```

# Fuentes de windows

```
sudo dnf install curl cabextract xorg-x11-font-utils fontconfig
sudo rpm -i --nodigest --nosignature https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
```

## Cambria
```
sudo dnf install cabextract
cd /tmp
curl -o PowerPointViewer.exe -fsSL "https://archive.org/download/PowerPointViewer_201801/PowerPointViewer.exe"

# Verify the download integrity
EXPECTED="249473568eba7a1e4f95498acba594e0f42e6581add4dead70c1dfb908a09423"
ACTUAL=$(sha256sum PowerPointViewer.exe | cut -d' ' -f1)
if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "Checksum verified successfully"
else
    echo "ERROR: Checksum mismatch. Expected: $EXPECTED"
    echo "       Actual:   $ACTUAL"
    exit 1
fi

cabextract -q PowerPointViewer.exe -F ppviewer.cab
cabextract -q ppviewer.cab -F '*.TTF' -F '*.TTC'

mkdir -p ~/.local/share/fonts/microsoft
mv *.TTF *.TTC ~/.local/share/fonts/microsoft/
fc-cache -f
```
# Compresión
```
sudo dnf install p7zip p7zip-plugins zstd pigz pbzip2
```

# LaTeX
```
sudo dnf install texlive-scheme-full make git
sudo dnf install google-roboto-fonts adobe-source-sans-pro-fonts texlive-fontawesome6
```

# Instalar APPS

## Navegador Chrome

```
sudo dnf install dnf-plugins-core
```

```
sudo dnf install fedora-workstation-repositories
sudo dnf config-manager setopt google-chrome.enabled=1
sudo dnf install google-chrome-stable
```

## Navegador Brave

```
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

sudo dnf install brave-browser
```

## Aplicaciones varias

```
sudo dnf install vlc gimp obs-studio shotcut
```

## ONLYOFFICE

```
flatpak install flathub org.onlyoffice.desktopeditors
```

## Obsidian
```
flatpak install flathub md.obsidian.Obsidian
```

# Gaming

Para configurar tu sistema para gaming en Fedora, consulta la documentación específica en [docs/gaming.md](docs/gaming.md).

# Desarrollo

Para configurar tu sistema para desarrollo en Fedora, consulta la documentación específica en [docs/development.md](docs/development.md).
