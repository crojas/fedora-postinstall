# Mejorar el comportamiento del gestor de paquetes.
```
sudo nano etc/dnf/dnf.conf
```
### Editar el fichero y agrear lo siguiente
```
[main]
fastestmirror=True
max_parallel_downloads=20
gpgcheck=True
installonly_limit=3
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
- **`installonly_limit=3`**
  Mantiene un máximo de 3 versiones del mismo kernel (u otros paquetes `installonly`). Cuando se instala uno nuevo, elimina los más antiguos si se supera el límite.
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
```
sudo dnf install google-chrome-stable vlc gimp obs-studio
```