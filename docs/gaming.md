# Instalar Steam
```
sudo dnf install steam
```

# Instalar [GameMode](https://github.com/FeralInteractive/gamemode)

Está en los repositorios oficiales de Fedora, no hace falta compilarlo.

```
sudo dnf install gamemode
```

## Test
```
gamemoded -t
```

# Gamescope

Compositor de Valve para juegos: limita FPS, escala con FSR y arregla juegos que se portan mal en pantalla completa. Opción de lanzamiento en Steam:

```
gamescope -W 2560 -H 1440 -f -- %command%
```

# NTSYNC

Módulo del kernel que imita la sincronización de Windows; GE-Proton lo usa si está cargado y en varios juegos sube harto los FPS.

```
echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf
sudo modprobe ntsync
```

# GE-Proton

El script baja la última versión a `~/.local/share/Steam/compatibilitytools.d/`. Después: Steam → Propiedades del juego → Compatibilidad → GE-Proton.

# ProtonUp-Qt
```
flatpak install flathub net.davidotek.pupgui2
```

# Ver rendimiento en juegos
```
sudo dnf install mangohud goverlay
```

### Para activar gamemode en steam
```
gamemoderun %command%
```

### Para activar mangohud en steam
```
mangohud %command%
```

### Ambos
```
mangohud gamemoderun %command%
```

# Grabar juegos con OBS

```
sudo dnf install obs-studio-plugin-vkcapture
```

En Steam usa `obs-gamecapture %command%` y en OBS agrega la fuente *Game Capture*.
