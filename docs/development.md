# Development tools

```
sudo dnf group install development-tools
```

## Librerias adicionales

```
sudo dnf install -y gcc gcc-c++ make cmake clang patch \
  glibc-devel openssl-devel zlib-devel pkg-config \
  readline-devel libffi-devel libyaml-devel \
  gdbm-devel ncurses-devel
```

- **Compiladores y herramientas base**: gcc, gcc-c++, clang, make y patch.
- **Librerías de desarrollo**: glibc-devel, openssl-devel, zlib-devel.
- **Dependencias de lenguajes (Ruby/Python)**: readline-devel, libffi-devel, libyaml-devel, gdbm-devel, ncurses-devel.
- **Utilidades de sistema**: pkg-config.

# Herramientas de terminal para agentes

```
sudo dnf install gh ripgrep fd-find fzf jq git-delta lazygit direnv distrobox
```

- **gh**: PRs, issues y CI de GitHub desde la terminal (los agentes lo usan harto).
- **ripgrep / fd / fzf / jq**: buscar en código y archivos, y manejar JSON, mucho más rápido.
- **git-delta / lazygit**: revisar los diffs que generan los agentes.
- **direnv**: variables de entorno por proyecto (`.envrc`).
- **distrobox**: contenedores para aislar entornos o agentes.

# Install ghostty

```
sudo dnf copr enable scottames/ghostty
sudo dnf install ghostty
```

# Install zsh

```
sudo dnf install zsh
zsh --version
```

### Cambiar shell

chsh -s $(which zsh)

### Oh My Zsh

```
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

### Tema

```
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

ZSH_THEME="powerlevel10k/powerlevel10k"

source ~/.zshrc
```

### Plugins

```
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

plugins=(git docker zsh-autosuggestions)

source ~/.zshrc
```

## Rust

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Golang

```
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.26.3.linux-amd64.tar.gz
```

### Agregar path a .zshrc

```
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
```

```
source ~/.zshrc
```

## UV (Python)
```
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## NVM (NodeJS)

```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
source ~/.zshrc
```

# Docker Engine

```
sudo dnf -y install dnf5-plugins
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Inicializar agregar el usuario para no usar sudo.

```
sudo systemctl enable --now docker
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
```

## Docker Compose

```
sudo curl -SL https://github.com/docker/compose/releases/download/v5.1.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

# Dbeaver

```
flatpak install flathub io.dbeaver.DBeaverCommunity
```

# Zed

```
curl -f https://zed.dev/install.sh | sh
```

# Cursor

```
sudo tee /etc/yum.repos.d/cursor.repo << EOL
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOL
```

```
sudo dnf install cursor
```

# OpenCode

```
curl -fsSL https://opencode.ai/install | bash
```

# Claude Code

```
curl -fsSL https://claude.ai/install.sh | bash
```

# Herdr

```
curl -fsSL https://herdr.dev/install.sh | sh
```

# Obsidian

```
flatpak install flathub md.obsidian.Obsidian
```
