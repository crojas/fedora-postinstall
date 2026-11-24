# Desarrollo (paso a paso)

Comandos equivalentes a lo que hace `install.sh` para la parte de desarrollo.

## Herramientas y librerías

```bash
sudo dnf group install development-tools
sudo dnf install gcc gcc-c++ make cmake clang patch git pkgconf-pkg-config \
  glibc-devel openssl-devel zlib-devel \
  readline-devel libffi-devel libyaml-devel gdbm-devel ncurses-devel
```

- **Compiladores y base:** gcc, gcc-c++, clang, cmake, make y patch.
- **Librerías:** glibc-devel, openssl-devel y zlib-devel.
- **Para compilar Ruby y Python:** readline-devel, libffi-devel, libyaml-devel, gdbm-devel y ncurses-devel.

## Herramientas de terminal para agentes

```bash
sudo dnf install gh ripgrep fd-find fzf jq git-delta lazygit direnv distrobox
```

- **gh**: PRs, issues y CI de GitHub desde la terminal (los agentes lo usan mucho).
- **ripgrep / fd / fzf / jq**: buscar en código y archivos, y manejar JSON, mucho más rápido.
- **git-delta / lazygit**: revisar los diffs que generan los agentes.
- **direnv**: variables de entorno por proyecto (`.envrc`).
- **distrobox**: contenedores para aislar entornos o agentes.

## Zsh + Oh My Zsh + Powerlevel10k

```bash
sudo dnf install zsh
RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
# Shell por defecto (usa la ruta de /etc/shells, no la de `which zsh`)
sudo usermod --shell /usr/bin/zsh "$USER"
```

En `~/.zshrc`:

```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git docker zsh-autosuggestions)
```

## Ghostty

```bash
sudo dnf copr enable scottames/ghostty
sudo dnf install ghostty
```

## Lenguajes

```bash
# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

# Go (última versión, en /usr/local/go)
V=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)
curl -fLO "https://go.dev/dl/$V.linux-amd64.tar.gz"   # arm64 en equipos ARM
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "$V.linux-amd64.tar.gz"

# Node.js LTS con NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.41.0/install.sh | PROFILE=/dev/null bash
source ~/.nvm/nvm.sh && nvm install --lts

# uv (Python)
curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
```

El script deja el PATH de todo esto en un solo bloque al final de `~/.bashrc` y `~/.zshrc`:

```bash
export GOROOT=/usr/local/go GOPATH="$HOME/go" NVM_DIR="$HOME/.nvm"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$GOPATH/bin:$GOROOT/bin:$HOME/.opencode/bin:$PATH"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

## Docker

```bash
sudo dnf install dnf5-plugins
sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # cierra sesión y vuelve a entrar
```

Compose viene como plugin: se usa con `docker compose`. Ojo: estar en el grupo `docker` equivale a tener permisos de root.

## Editores

```bash
# Zed
curl -f https://zed.dev/install.sh | sh

# Cursor
sudo tee /etc/yum.repos.d/cursor.repo <<'EOF'
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
EOF
sudo dnf install cursor

# DBeaver
flatpak install flathub io.dbeaver.DBeaverCommunity
```

## Agentes de IA y notas

```bash
curl -fsSL https://claude.ai/install.sh | bash                    # Claude Code
curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh  # Codex CLI
curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path  # OpenCode
curl -fsSL https://herdr.dev/install.sh | sh                      # Herdr
flatpak install flathub md.obsidian.Obsidian                       # Obsidian
```
