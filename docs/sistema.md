# Sistema, multimedia y apps (paso a paso)

Comandos equivalentes a lo que hace `install.sh`, por si quieres hacerlo a mano o entender cada paso. El script además verifica, reintenta y registra todo en el log.

## Optimizar DNF

```bash
sudo dnf install dnf5-plugins
sudo dnf config-manager setopt max_parallel_downloads=20 fastestmirror=True installonly_limit=3 \
  clean_requirements_on_remove=True best=False skip_if_unavailable=True keepcache=False
```

- **`max_parallel_downloads=20`**: hasta 20 descargas en paralelo.
- **`fastestmirror=True`**: elige el mirror más rápido.
- **`installonly_limit=3`**: guarda 3 kernels; si uno nuevo falla, arrancas el anterior desde el menú de inicio.
- **`clean_requirements_on_remove=True`**: al desinstalar, borra también las dependencias que ya nadie usa.
- **`best=False`**: si la última versión de un paquete no se puede instalar, usa la anterior en vez de fallar.
- **`skip_if_unavailable=True`**: si un repositorio no responde, sigue con los demás.
- **`keepcache=False`**: borra los `.rpm` descargados después de instalarlos.

## Snapshots automáticos (solo si `/` está en Btrfs)

```bash
sudo dnf install snapper libdnf5-plugin-actions btrfs-assistant
sudo snapper -c root create-config /
sudo snapper -c root set-config NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 TIMELINE_CREATE=no
sudo systemctl enable --now snapper-cleanup.timer
```

Para que dnf cree un snapshot antes y después de cada instalación, crea `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions` con el ejemplo de `man libdnf5-actions` (el script lo hace solo).

**Volver atrás:**

- Con interfaz gráfica: Btrfs Assistant → *Snapper* → elige el snapshot → *Restore* y reinicia.
- Desde una terminal (sirve también en una consola de texto con Ctrl+Alt+F3): `sudo snapper list` para ver los números y `sudo snapper undochange <n>..0` para deshacer todo lo que cambió desde el snapshot `<n>`.

**Qué no cubre:**

- `/boot` no entra en el snapshot. Si el problema vino con un kernel nuevo, elige el kernel anterior en el menú de inicio.
- `/home` no se toca. `/var` sí vuelve atrás, incluidos los volúmenes de Docker y las apps Flatpak del sistema.

## Límites de inotify

```bash
printf 'fs.inotify.max_user_instances = 1024\nfs.inotify.max_user_watches = 524288\n' |
  sudo tee /etc/sysctl.d/90-fedora-postinstall.conf
sudo sysctl --system
```

## Repositorios: [RPM Fusion](https://rpmfusion.org), Flathub y OpenH264

```bash
V=$(rpm -E %fedora)
# Verifica la firma del paquete con las llaves que publica Fedora
sudo dnf install distribution-gpg-keys
sudo rpmkeys --import /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-{free,nonfree}-fedora-$V
sudo dnf install --setopt=localpkg_gpgcheck=1 \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$V.noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$V.noarch.rpm
sudo dnf install rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak remote-modify --enable --no-filter flathub

sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
```

## Firmware vía [LVFS](https://fwupd.org/)

```bash
sudo fwupdmgr refresh --force
sudo fwupdmgr update
```

Al reiniciar se instala el firmware, y puede tardar unos minutos. Hazlo con el cargador conectado y sin apagar el equipo.

## Drivers NVIDIA

```bash
# Solo con Secure Boot: crear la llave ANTES de instalar el driver
sudo dnf install akmods mokutil
sudo kmodgenca -a

sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
```

**GPU antiguas:**

- **Maxwell y Pascal (GTX 900/10xx, desde Fedora 44):** usa `akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda`.
- **Kepler (GTX 600/700):** usa la serie `470xx`.

**Con Secure Boot**, antes de reiniciar:

1. Ejecuta `sudo mokutil --import /etc/pki/akmods/certs/public_key.der` y elige una contraseña de un solo uso.
2. Al reiniciar aparece una pantalla azul (MOK): *Enroll MOK* → *Continue* → *Yes*, e ingresa esa contraseña.

## Extensiones de GNOME

```bash
flatpak install flathub com.mattjakeman.ExtensionManager
```

Extension Manager permite buscar, instalar, activar y configurar extensiones de GNOME desde una app.

## Codecs multimedia

```bash
sudo dnf install --allowerasing ffmpeg ffmpeg-libs libva libva-utils libdvdcss
sudo dnf install @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
sudo dnf group install sound-and-video
# Firmwares extra: se listan del repo tainted y se instalan con todos los repos activos
sudo dnf install $(dnf repoquery -q --repo=rpmfusion-nonfree-tainted --qf '%{name}\n' '*-firmware')
```

## Aceleración de video por hardware

```bash
sudo dnf install intel-media-driver                          # Intel
sudo dnf install --allowerasing mesa-va-drivers-freeworld    # AMD
sudo dnf install libva-nvidia-driver                         # NVIDIA
```

## Fuentes de Microsoft

```bash
sudo dnf install curl cabextract xorg-x11-font-utils fontconfig
curl -fLO https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
echo "55d7f3a86533225634ff3ea2384b4356d9665a29cc7eeacff16602a1714afbb4  msttcore-fonts-installer-2.6-1.noarch.rpm" | sha256sum -c
sudo rpm -i --nodigest --nosignature msttcore-fonts-installer-2.6-1.noarch.rpm
```

**Cambria** no viene en ese paquete; se saca del PowerPoint Viewer:

```bash
cd /tmp
curl -fLo PowerPointViewer.exe https://archive.org/download/PowerPointViewer_201801/PowerPointViewer.exe
echo "249473568eba7a1e4f95498acba594e0f42e6581add4dead70c1dfb908a09423  PowerPointViewer.exe" | sha256sum -c &&
  cabextract -q -F ppviewer.cab PowerPointViewer.exe &&
  cabextract -q -F CAMBRIA.TTC ppviewer.cab &&
  mkdir -p ~/.local/share/fonts/microsoft &&
  mv CAMBRIA.TTC ~/.local/share/fonts/microsoft/ &&
  fc-cache -f
```

## Compresión

```bash
sudo dnf install 7zip zstd pigz pbzip2
```

## LaTeX

```bash
sudo dnf install texlive-scheme-full make google-roboto-fonts adobe-source-sans-pro-fonts texlive-fontawesome6
```

En Fedora 43 usa `texlive-fontawesome5`, porque la 6 no existe ahí.

## Navegadores

```bash
# Chrome (solo x86_64)
sudo dnf install fedora-workstation-repositories
sudo dnf config-manager setopt google-chrome.enabled=1
sudo dnf install google-chrome-stable

# Brave
sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
sudo dnf install brave-browser
```

## Apps

```bash
sudo dnf install vlc gimp obs-studio obs-studio-plugin-vkcapture shotcut
flatpak install flathub org.onlyoffice.desktopeditors
```
