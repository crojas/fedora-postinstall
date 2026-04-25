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

## Rust

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

## Golang

```
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.26.1.linux-amd64.tar.gz
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
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
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

# Visual Studio Code

```
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
```

```
dnf check-update
sudo dnf install code # or code-insiders
```

# Antigravity

```
sudo tee /etc/yum.repos.d/antigravity.repo << EOL
[antigravity-rpm]
name=Antigravity RPM Repository
baseurl=https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm
enabled=1
gpgcheck=0
EOL
```

```
sudo dnf makecache
sudo dnf install antigravity
```

# OpenCode

```
curl -fsSL https://opencode.ai/install | bash
```
