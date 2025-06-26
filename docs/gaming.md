# Instalar Steam
```
sudo dnf install steam
```

# Instalar [GameMode](https://github.com/FeralInteractive/gamemode)
```
sudo dnf install meson systemd-devel pkg-config git dbus-devel inih-devel
```
## instalar: clonar el repositorio de git en home/user

```
git clone https://github.com/FeralInteractive/gamemode.git
cd gamemode
git checkout 1.8.2 # omit to build the master branch
./bootstrap.sh
```

## Agrega tu usuario al grupo gamemode (un tema de permisos)
```
sudo usermod -aG gamemode $(whoami)
```
## Activar gamemode al inicio para tu usuario
```
sudo systemctl enable --now gamemoded.service
```
## Test
```
gamemoded -t
```
## Ver si se esta ejecutando
```
gamemoded -s
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