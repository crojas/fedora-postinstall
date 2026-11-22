# Gaming (paso a paso)

Comandos equivalentes a lo que hace `install.sh` para jugar. Steam viene de RPM Fusion, así que primero hay que agregar ese repositorio (ver [sistema.md](sistema.md)).

## Steam y herramientas

```bash
sudo dnf install steam gamescope gamemode mangohud goverlay
flatpak install flathub net.davidotek.pupgui2   # ProtonUp-Qt
```

- **GameMode**: da prioridad al juego mientras corre. Para probarlo: `gamemoded -t`.
- **MangoHud**: muestra FPS, temperaturas y uso de CPU/GPU; GOverlay lo configura con interfaz gráfica.
- **Gamescope**: compositor de Valve que limita FPS, escala con FSR y arregla juegos que se portan mal en pantalla completa.
- **ProtonUp-Qt**: instala y actualiza versiones de Proton con interfaz gráfica.

## NTSYNC

Módulo del kernel que imita la sincronización de Windows. GE-Proton lo usa si está cargado y en varios juegos mejora bastante los FPS.

```bash
echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf
sudo modprobe ntsync
```

## GE-Proton

El script baja la última versión desde GitHub, verifica su sha512 y la deja en `~/.local/share/Steam/compatibilitytools.d/`. A mano:

```bash
cd /tmp
V=GE-Proton11-12   # última versión: github.com/GloriousEggroll/proton-ge-custom/releases
curl -fLO "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$V/$V-x86_64.tar.gz"
curl -fLO "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$V/$V-x86_64.sha512sum"
sha512sum -c "$V-x86_64.sha512sum" &&
  mkdir -p ~/.local/share/Steam/compatibilitytools.d &&
  tar -xzf "$V-x86_64.tar.gz" -C ~/.local/share/Steam/compatibilitytools.d
```

Después: Steam → Propiedades del juego → Compatibilidad → GE-Proton (reinicia Steam si no aparece).

## Opciones de lanzamiento en Steam

| Para | Opción |
|---|---|
| Modo rendimiento | `gamemoderun %command%` |
| FPS en pantalla | `mangohud %command%` |
| Ambos | `mangohud gamemoderun %command%` |
| Limitar FPS / escalar con FSR | `gamescope -W 2560 -H 1440 -f -- %command%` |
| Grabar el juego con OBS | `obs-gamecapture %command%` |

## Grabar juegos con OBS

```bash
sudo dnf install obs-studio-plugin-vkcapture
```

En Steam usa `obs-gamecapture %command%` y en OBS agrega la fuente *Game Capture*. Captura directo desde Vulkan/OpenGL, sin la latencia de grabar la pantalla.
