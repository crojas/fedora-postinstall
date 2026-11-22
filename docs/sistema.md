# Sistema, multimedia y apps (paso a paso)

Los mismos comandos que corre `install.sh`, por si quieres hacerlo a mano o entender qué hace cada paso.

# Snapshots automáticos con snapper (solo si `/` está en Btrfs)

```
sudo dnf install snapper libdnf5-plugin-actions btrfs-assistant
sudo snapper -c root create-config /
sudo snapper -c root set-config NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 TIMELINE_CREATE=no
sudo systemctl enable --now snapper-cleanup.timer
```

Para que dnf cree un snapshot antes y después de cada instalación, crea `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions` con el ejemplo de `man libdnf5-actions` (el script lo hace solo). Para restaurar: abre **Btrfs Assistant** → *Snapper* → elige el snapshot → *Restore* y reinicia.

# Límites de inotify

```
echo -e "fs.inotify.max_user_instances = 1024\nfs.inotify.max_user_watches = 524288" | sudo tee /etc/sysctl.d/90-fedora-postinstall.conf
sudo sysctl --system
```

# Optimizar DNF

```
sudo nano /etc/dnf/dnf.conf
```

### Edita el archivo y agrega lo siguiente

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
sudo dnf install @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
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
