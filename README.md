Script de postinstalación para Fedora 42 orientado a desarrollo, edición multimedia y gaming.

Configura automáticamente:

- Repositorios adicionales
- Drivers de hardware
- Codecs multimedia completos
- Herramientas de edición de imágenes y video.
- Herramientas de desarrollo.
- Steam y optimizaciones para jugar.

Transforma una instalación básica en una estación de trabajo lista para uso profesional.

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
sudo rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
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
sudo dnf install vlc gimp obs-studio
```

# Gaming

Para configurar tu sistema para gaming en Fedora, consulta la documentación específica en [docs/gaming.md](docs/gaming.md).

# Desarrollo

Para configurar tu sistema para desarrollo en Fedora, consulta la documentación específica en [docs/development.md](docs/development.md).
