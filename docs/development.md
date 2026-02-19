# Install ghostty

```
dnf copr enable scottames/ghostty
dnf install ghostty
```

# Install zsh

```sudo dnf install zsh
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
sudo dnf install -y gcc gcc-c++ make clang patch \
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
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.26.0.linux-amd64.tar.gz
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

## NVM (NodeJS)

```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
source ~/.zshrc
```

## RVM (Ruby)

```
gpg2 --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
\curl -sSL https://get.rvm.io | bash -s stable
source ~/.zshrc
```

## Conda (Python)

```
curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
bash Miniforge3-$(uname)-$(uname -m).sh
source ~/.zshrc
```

### Quitar conda de inicio

```
conda config --set auto_activate_base false
```

# Docker Engine

```
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
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
sudo curl -SL https://github.com/docker/compose/releases/download/v2.38.2/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
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
