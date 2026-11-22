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
