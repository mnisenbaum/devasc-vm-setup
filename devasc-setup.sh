#!/usr/bin/env bash
# =============================================================================
# devasc-setup.sh  -  Transforma um Ubuntu 24.04 recém-instalado numa DEVASC-VM
# Curso: Cisco NetAcad DevNet Associate (DEVASC)            ABRedes - v0.4
# Arquiteturas: amd64 (Intel/AMD) e arm64 (Apple Silicon via VMware Fusion/UTM)
# -----------------------------------------------------------------------------
# Repositório: https://github.com/mnisenbaum/devasc-vm-setup
#
# Uso:
#   git clone https://github.com/mnisenbaum/devasc-vm-setup.git
#   cd devasc-vm-setup
#   sudo ./devasc-setup.sh                 # instalação completa
#   sudo ./devasc-setup.sh --no-desktop    # sem MATE/xrdp (servidor)
#   sudo ./devasc-setup.sh --no-autologin  # sem login automático (melhor para quem usa RDP)
#   sudo ./devasc-setup.sh --no-api-simulator  # não instala o School Library API (lab 4.5.5)
#   sudo ./devasc-setup.sh --only venv     # roda só uma etapa (ver lista abaixo)
#
# Etapas: check base desktop xrdp tools docker gui-apps user network api-simulator venv labs desktop-icons branding guest finish
#
# O script é idempotente: pode ser rodado de novo sem quebrar nada.
# Log completo em /var/log/devasc-setup.log
# =============================================================================
set -Eeuo pipefail

# ------------------------------------------------------------------ CONFIG
DEVASC_USER="devasc"
DEVASC_PASS="${DEVASC_PASS:-}"      # só usada se o script precisar CRIAR o usuário (pergunta no início)
DEVASC_UID=900                      # mesmo uid da VM original
VM_HOSTNAME="labvm"                 # prompt dos roteiros: devasc@labvm
VENV_DIR="/opt/devasc/venv"         # venv global, ativado no .bashrc
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LABS_SRC="${LABS_SRC:-$SCRIPT_DIR/labs/devnet-src}"   # cópia de ~/labs/devnet-src
ASSETS="${ASSETS:-$SCRIPT_DIR/assets}"                # simulador, wallpaper, pylintrc
REPO_TARBALL="https://github.com/mnisenbaum/devasc-vm-setup/archive/refs/heads/main.tar.gz"
LOG=/var/log/devasc-setup.log

# Pacotes Python dos labs (venv global)
PY_PKGS=(
  requests Faker PyYAML xmltodict                # 3.6.6, 4.5.5, 4.9.2, 8.6.7
  flask pyotp cryptography pyopenssl             # 6.2.7, 6.5.10
  ncclient pyang lxml                            # 8.3.5, 8.3.6
  netmiko paramiko textfsm jinja2                # automação geral
  ansible ansible-pylibssh                       # 7.4.7, 7.4.8
  webexteamssdk                                  # 8.6.7
  pylint autopep8 pytest                         # VS Code / 3.5.7
)
PY_PKGS_PYATS=( "pyats[full]" )                  # 7.6.3 (instalado à parte: pode falhar no arm64)

WITH_DESKTOP=1
AUTOLOGIN=1
WITH_API_SIM=1
ONLY=""

# ------------------------------------------------------------------ UTIL
C_OK='\e[1;32m'; C_INFO='\e[1;34m'; C_WARN='\e[1;33m'; C_ERR='\e[1;31m'; C_0='\e[0m'
info() { echo -e "${C_INFO}[devasc]${C_0} $*"; }
ok()   { echo -e "${C_OK}[  ok  ]${C_0} $*"; }
warn() { echo -e "${C_WARN}[aviso ]${C_0} $*"; WARNINGS+=("$*"); }
die()  { echo -e "${C_ERR}[ erro ]${C_0} $*"; exit 1; }
WARNINGS=()
trap 'echo -e "${C_ERR}[ erro ]${C_0} falhou na linha $LINENO: $BASH_COMMAND (veja $LOG)"' ERR

apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }
as_user() { sudo -u "$DEVASC_USER" -H bash -c "$*"; }
step() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-desktop) WITH_DESKTOP=0 ;;
    --no-autologin) AUTOLOGIN=0 ;;
    --no-api-simulator) WITH_API_SIM=0 ;;
    --only) ONLY="$2"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "opção desconhecida: $1" ;;
  esac; shift
done

[[ $EUID -eq 0 ]] || die "Rode com sudo:  sudo $0"
exec > >(tee -a "$LOG") 2>&1
echo "==================== $(date) ===================="

# Se labs/ ou assets/ não estão ao lado do script (ex.: só o .sh foi copiado),
# baixa o repositório do GitHub e usa as pastas de lá.
if [[ ! -d "$LABS_SRC" || ! -d "$ASSETS" ]]; then
  info "Pastas labs/ ou assets/ não encontradas ao lado do script. Baixando do GitHub..."
  SRC_TMP="$(mktemp -d /tmp/devasc-vm-setup.XXXX)"
  if curl -fsSL "$REPO_TARBALL" | tar -xz -C "$SRC_TMP" --strip-components=1; then
    [[ -d "$LABS_SRC" ]] || LABS_SRC="$SRC_TMP/labs/devnet-src"
    [[ -d "$ASSETS" ]]   || ASSETS="$SRC_TMP/assets"
    ok "Arquivos baixados em $SRC_TMP"
  else
    warn "Não consegui baixar $REPO_TARBALL - labs e simulador serão pulados."
  fi
fi

ARCH="$(dpkg --print-architecture)"          # amd64 | arm64
VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"

# Senha do devasc: perguntada logo no início, e só se o usuário ainda não existir
# (quem já criou "devasc" no instalador do Ubuntu mantém a senha que escolheu).
if [[ -z "$ONLY" || "$ONLY" == "user" ]] && ! id "$DEVASC_USER" >/dev/null 2>&1 && [[ -z "$DEVASC_PASS" ]]; then
  echo "O usuário '$DEVASC_USER' não existe e será criado."
  while true; do
    read -rsp "  Escolha a senha do $DEVASC_USER: " P1 </dev/tty; echo
    read -rsp "  Repita a senha: " P2 </dev/tty; echo
    [[ -n "$P1" && "$P1" == "$P2" ]] && { DEVASC_PASS="$P1"; break; }
    echo "  As senhas não conferem (ou estão vazias). Tente de novo."
  done
fi

# ------------------------------------------------------------------ 1. CHECK
if step check; then
  info "Verificando o sistema..."
  . /etc/os-release
  [[ "$ID" == "ubuntu" ]] || die "Este script é para Ubuntu (encontrado: $ID)."
  [[ "$VERSION_ID" == "24.04" ]] || warn "Testado no Ubuntu 24.04; você está no $VERSION_ID."
  [[ "$ARCH" == "amd64" || "$ARCH" == "arm64" ]] || die "Arquitetura não suportada: $ARCH"
  curl -fsS --max-time 10 -o /dev/null https://download.docker.com || die "Sem acesso à internet."
  ok "Ubuntu $VERSION_ID / $ARCH / virtualização: $VIRT"
fi

# ------------------------------------------------------------------ 2. BASE
if step base; then
  info "Atualizando o sistema e instalando pacotes base..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
  apt_install ca-certificates curl wget gnupg lsb-release software-properties-common \
    build-essential python3 python3-venv python3-dev python3-pip \
    libssl-dev libffi-dev libxml2-dev libxslt1-dev zlib1g-dev \
    git vim nano less tree jq unzip zip bash-completion man-db
  hostnamectl set-hostname "$VM_HOSTNAME"
  # igual à VM original: 127.0.1.1  labvm.vm  labvm
  sed -i "/^127.0.1.1/d" /etc/hosts
  sed -i "2i 127.0.1.1\t$VM_HOSTNAME.vm\t$VM_HOSTNAME" /etc/hosts
  ok "Base instalada (hostname: $VM_HOSTNAME)"
fi

# ------------------------------------------------------------------ 3. DESKTOP MATE
if step desktop && [[ $WITH_DESKTOP -eq 1 ]]; then
  info "Instalando o desktop MATE + LightDM (demora)..."
  echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections
  DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-mate-core lightdm slick-greeter \
    mate-terminal caja pluma atril engrampa ubuntu-mate-themes ubuntu-mate-wallpapers \
    fonts-dejavu fonts-liberation dconf-cli
  echo /usr/sbin/lightdm > /etc/X11/default-display-manager
  DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm || true
  systemctl set-default graphical.target
  ok "MATE instalado"
fi

# ------------------------------------------------------------------ 4. XRDP
if step xrdp && [[ $WITH_DESKTOP -eq 1 ]]; then
  info "Instalando xrdp (acesso por Área de Trabalho Remota)..."
  apt_install xrdp xorgxrdp
  adduser xrdp ssl-cert >/dev/null 2>&1 || true
  systemctl enable --now xrdp
  ok "xrdp ativo na porta 3389"
fi

# ------------------------------------------------------------------ 5. FERRAMENTAS DE REDE / SISTEMA
if step tools; then
  info "Ferramentas de rede e utilitários dos labs..."
  apt_install openssh-server sshpass net-tools dnsutils inetutils-traceroute iputils-ping \
    iproute2 telnet ftp tcpdump nmap whois netcat-openbsd sqlite3 sqlitebrowser
  # 7.4.8: o Ansible faz SSH com senha na própria VM
  mkdir -p /etc/ssh/sshd_config.d
  echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/10-devasc.conf
  systemctl enable --now ssh
  ok "Ferramentas instaladas; SSH ativo"
fi

# ------------------------------------------------------------------ 6. DOCKER CE (oficial)
if step docker; then
  info "Instalando Docker CE (repositório oficial, $ARCH)..."
  apt-get remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  ok "Docker $(docker --version | awk '{print $3}' | tr -d ,)"
fi

# ------------------------------------------------------------------ 7. APPS GRÁFICOS
if step gui-apps && [[ $WITH_DESKTOP -eq 1 ]]; then
  info "VS Code, Chromium e draw.io..."
  # VS Code - repositório Microsoft (amd64 e arm64)
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list
  echo "code code/add-microsoft-repo boolean false" | debconf-set-selections
  apt-get update
  apt_install code
  # Chromium - snap (amd64 e arm64)
  snap list chromium >/dev/null 2>&1 || snap install chromium
  # draw.io - .deb do GitHub para a arquitetura certa
  if ! dpkg -s drawio >/dev/null 2>&1; then
    DRAWIO_URL="$(curl -fsSL https://api.github.com/repos/jgraph/drawio-desktop/releases/latest \
      | grep -oE "https://[^\"]+drawio-${ARCH}-[0-9.]+\.deb" | head -1)" || true
    if [[ -n "$DRAWIO_URL" ]]; then
      curl -fsSL "$DRAWIO_URL" -o /tmp/drawio.deb && apt_install /tmp/drawio.deb && rm -f /tmp/drawio.deb
    else
      warn "Não achei o .deb do draw.io para $ARCH (instale depois: snap install drawio)."
    fi
  fi
  ok "Apps gráficos instalados"
fi

# ------------------------------------------------------------------ 8. USUÁRIO devasc
if step user; then
  info "Configurando o usuário $DEVASC_USER..."
  if ! id "$DEVASC_USER" >/dev/null 2>&1; then
    if getent passwd "$DEVASC_UID" >/dev/null || getent group "$DEVASC_UID" >/dev/null; then
      useradd -m -s /bin/bash -U "$DEVASC_USER"
    else
      groupadd -g "$DEVASC_UID" "$DEVASC_USER"
      useradd -m -s /bin/bash -u "$DEVASC_UID" -g "$DEVASC_UID" "$DEVASC_USER"
    fi
  fi
  # Se o usuário foi criado agora, define a senha escolhida no início.
  # Se já existia (criado no instalador do Ubuntu), a senha dele NÃO é alterada.
  if [[ -n "$DEVASC_PASS" ]]; then echo "$DEVASC_USER:$DEVASC_PASS" | chpasswd; fi
  for g in sudo docker ssl-cert dialout wireshark; do
    getent group "$g" >/dev/null && usermod -aG "$g" "$DEVASC_USER"
  done
  as_user "mkdir -p ~/Desktop ~/Documents ~/Downloads ~/Pictures ~/Videos ~/labs"
  # sudo sem senha (igual à VM original)
  echo "$DEVASC_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-devasc
  chmod 0440 /etc/sudoers.d/90-devasc
  visudo -cf /etc/sudoers.d/90-devasc >/dev/null || { rm -f /etc/sudoers.d/90-devasc; warn "sudoers inválido - removido"; }
  # git: igual à VM original + branch master (bate com os roteiros)
  as_user "git config --global user.name 'NetAcad DEVASC'"
  as_user "git config --global user.email 'changeme@example.com'"
  as_user "git config --global init.defaultBranch master"
  # login automático no LightDM (igual à VM original)
  if [[ $WITH_DESKTOP -eq 1 ]]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    if [[ $AUTOLOGIN -eq 1 ]]; then
      printf '[Seat:*]\nautologin-guest=false\nautologin-user=%s\nautologin-user-timeout=0\n' "$DEVASC_USER" \
        > /etc/lightdm/lightdm.conf.d/10-devasc-user.conf
    else
      rm -f /etc/lightdm/lightdm.conf.d/10-devasc-user.conf
    fi
  fi
  # xrdp abre sessão MATE
  [[ $WITH_DESKTOP -eq 1 ]] && as_user "echo mate-session > ~/.xsession"
  ok "Usuário $DEVASC_USER pronto"
fi

# ------------------------------------------------------------------ 8b. REDE INTERNA DOS LABS
# A VM original tem uma interface dummy0 com 192.0.2.1-5/32.
# O lab 7.4.8 (Ansible + Apache) usa 192.0.2.3 como "servidor web" (é a própria VM).
if step network; then
  info "Criando a interface dummy0 (192.0.2.1-5/32)..."
  cat > /usr/local/sbin/devasc-dummy0 <<'EOF'
#!/bin/sh
# Interface virtual usada pelos labs DEVASC (igual à DEVASC-VM original)
ip link show dummy0 >/dev/null 2>&1 || ip link add dummy0 type dummy
for i in 1 2 3 4 5; do ip addr replace 192.0.2.$i/32 dev dummy0; done
ip link set dummy0 up
EOF
  chmod 0755 /usr/local/sbin/devasc-dummy0
  cat > /etc/systemd/system/devasc-dummy0.service <<'EOF'
[Unit]
Description=DEVASC lab dummy interface (192.0.2.1-5)
After=network-pre.target
Before=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/devasc-dummy0
ExecStop=/sbin/ip link del dummy0

[Install]
WantedBy=multi-user.target
EOF
  # NetworkManager (Ubuntu Desktop) não deve mexer na dummy0
  if [[ -d /etc/NetworkManager/conf.d ]]; then
    printf '[keyfile]\nunmanaged-devices=interface-name:dummy0\n' > /etc/NetworkManager/conf.d/90-devasc-dummy0.conf
    systemctl reload NetworkManager 2>/dev/null || true
  fi
  systemctl daemon-reload
  systemctl enable --now devasc-dummy0.service
  ok "dummy0 ativa: $(ip -br addr show dummy0 | cut -c1-80)"
fi

# ------------------------------------------------------------------ 8c. SCHOOL LIBRARY API SIMULATOR (lab 4.5.5)
# Mesmo app da VM original (/opt/API-SIMULATOR), adaptado para Python 3.12 (flask-restx).
# Responde em http://library.demo.local (192.0.2.1:80), usuário cisco / Cisco123!
if step api-simulator && [[ $WITH_API_SIM -eq 1 ]]; then
  info "Instalando o School Library API Simulator..."
  if [[ -d "$ASSETS/api-simulator" ]]; then
    mkdir -p /opt/API-SIMULATOR
    cp -r "$ASSETS/api-simulator/." /opt/API-SIMULATOR/
    [[ -x /opt/API-SIMULATOR/venv/bin/python ]] || python3 -m venv /opt/API-SIMULATOR/venv
    /opt/API-SIMULATOR/venv/bin/pip install -q --upgrade pip
    /opt/API-SIMULATOR/venv/bin/pip install -q -r /opt/API-SIMULATOR/requirements.txt
    grep -q "library.demo.local" /etc/hosts || echo "192.0.2.1 library.demo.local" >> /etc/hosts
    cat > /etc/systemd/system/devasc-api-simulator.service <<'EOF'
[Unit]
Description=DEVASC School Library API Simulator (library.demo.local)
Requires=devasc-dummy0.service
After=devasc-dummy0.service network.target

[Service]
WorkingDirectory=/opt/API-SIMULATOR
Environment=SIM_HOST=192.0.2.1 SIM_PORT=80
ExecStart=/opt/API-SIMULATOR/venv/bin/python api-simulator.py
DynamicUser=yes
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable devasc-api-simulator.service
    systemctl restart devasc-api-simulator.service
    sleep 3
    if curl -fsS --max-time 5 -o /dev/null http://library.demo.local/api/v1/books; then
      ok "School Library API em http://library.demo.local"
    else
      warn "School Library API não respondeu (veja: journalctl -u devasc-api-simulator)"
    fi
  else
    warn "Pasta $ASSETS/api-simulator não encontrada - lab 4.5.5 sem simulador."
  fi
fi

# ------------------------------------------------------------------ 9. VENV GLOBAL
if step venv; then
  info "Criando o venv global em $VENV_DIR..."
  mkdir -p "$(dirname "$VENV_DIR")"
  [[ -x "$VENV_DIR/bin/python" ]] || python3 -m venv "$VENV_DIR"
  chown -R "$DEVASC_USER:$DEVASC_USER" "$(dirname "$VENV_DIR")"
  as_user "$VENV_DIR/bin/pip install --upgrade pip setuptools wheel"
  as_user "$VENV_DIR/bin/pip install ${PY_PKGS[*]}"
  if as_user "$VENV_DIR/bin/pip install '${PY_PKGS_PYATS[*]}'"; then
    ok "pyATS/Genie instalados"
  else
    warn "pyATS não instalou em $ARCH/Python $(python3 -V | cut -d' ' -f2). Lab 7.6.3 fica pendente."
  fi
  # Ansible: collection Cisco IOS (lab 7.4.7)
  as_user "$VENV_DIR/bin/ansible-galaxy collection install cisco.ios --upgrade" || warn "Falha ao instalar cisco.ios"
  # ativa no .bashrc (bloco único e idempotente)
  BRC="/home/$DEVASC_USER/.bashrc"
  sed -i '/# >>> devasc venv >>>/,/# <<< devasc venv <<</d' "$BRC"
  cat >> "$BRC" <<EOF
# >>> devasc venv >>>
# Ambiente Python global dos labs DEVASC. Para sair: deactivate
if [ -z "\$VIRTUAL_ENV" ] && [ -f $VENV_DIR/bin/activate ]; then
  VIRTUAL_ENV_DISABLE_PROMPT=1 . $VENV_DIR/bin/activate
fi
# <<< devasc venv <<<
EOF
  # VS Code usa o mesmo interpretador
  as_user "mkdir -p ~/.config/Code/User"
  SETTINGS="/home/$DEVASC_USER/.config/Code/User/settings.json"
  [[ -s "$SETTINGS" ]] || as_user "cat > ~/.config/Code/User/settings.json" <<EOF
{
  "python.defaultInterpreterPath": "$VENV_DIR/bin/python",
  "window.zoomLevel": 2,
  "extensions.autoUpdate": false,
  "update.mode": "none",
  "workbench.startupEditor": "none",
  "telemetry.telemetryLevel": "off"
}
EOF
  if command -v code >/dev/null; then
    as_user "code --install-extension ms-python.python --force" >/dev/null 2>&1 || warn "Extensão Python do VS Code não instalou"
  fi
  ok "venv global pronto ($("$VENV_DIR/bin/python" -V))"
fi

# ------------------------------------------------------------------ 10. LABS
if step labs; then
  info "Copiando ~/labs/devnet-src..."
  if [[ -d "$LABS_SRC" ]]; then
    mkdir -p "/home/$DEVASC_USER/labs/devnet-src"
    cp -rn "$LABS_SRC/." "/home/$DEVASC_USER/labs/devnet-src/"
    chown -R "$DEVASC_USER:$DEVASC_USER" "/home/$DEVASC_USER/labs"
    ok "Labs copiados de $LABS_SRC"
  else
    warn "Pasta de labs não encontrada ($LABS_SRC). Defina LABS_SRC=/caminho e rode: sudo ./devasc-setup.sh --only labs"
  fi
fi

# ------------------------------------------------------------------ 11. ÍCONES DO DESKTOP
if step desktop-icons && [[ $WITH_DESKTOP -eq 1 ]]; then
  info "Criando atalhos na área de trabalho..."
  D="/home/$DEVASC_USER/Desktop"
  mk() {  # nome arquivo exec icone [terminal]
    cat > "$D/$2.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$1
Exec=$3
Icon=$4
Terminal=false
EOF
    chmod +x "$D/$2.desktop"
  }
  mk "Terminal"              terminal  "mate-terminal"                 utilities-terminal
  mk "Visual Studio Code"    code      "code"                          vscode
  mk "Chromium Web Browser"  chromium  "chromium"                      chromium
  mk "draw.io"               drawio    "drawio"                        drawio
  mk "Keyboard"              mate-keyboard "mate-keyboard-properties"  preferences-desktop-keyboard
  mk "DPI Scaling"           dpi-scaling   "devasc-dpi-scaling"        preferences-desktop-display
  # atalho da pasta labs (tipo Link, igual ao original)
  printf '[Desktop Entry]\nVersion=1.0\nType=Link\nName=labs\nIcon=user-bookmarks\nURL=/home/%s/labs\n' "$DEVASC_USER" > "$D/labs.desktop"
  chmod +x "$D/labs.desktop"
  # "DPI Scaling": alterna a escala da tela entre 1.0 e 0.8 (o original usava xrandr --scale 0.8x0.8)
  cat > /usr/local/bin/devasc-dpi-scaling <<'EOF'
#!/bin/sh
OUT=$(xrandr | awk '/ connected/{print $1; exit}')
CUR=$(xrandr --verbose | awk -v o="$OUT" '$1==o{f=1} f&&/Transform:/{print $2; exit}')
case "$CUR" in 0.8*) xrandr --output "$OUT" --scale 1x1 ;; *) xrandr --output "$OUT" --scale 0.8x0.8 ;; esac
EOF
  chmod 0755 /usr/local/bin/devasc-dpi-scaling
  chown -R "$DEVASC_USER:$DEVASC_USER" "$D"
  # marca os atalhos como confiáveis (MATE/caja)
  for f in "$D"/*.desktop; do as_user "gio set '$f' metadata::trusted true" 2>/dev/null || true; done
  ok "Atalhos criados"
fi

# ------------------------------------------------------------------ 11b. VISUAL / PYLINT (igual à VM original)
if step branding; then
  if [[ -f "$ASSETS/pylintrc" ]]; then
    install -o "$DEVASC_USER" -g "$DEVASC_USER" -m 0644 "$ASSETS/pylintrc" "/home/$DEVASC_USER/.pylintrc"
  fi
  if [[ $WITH_DESKTOP -eq 1 && -f "$ASSETS/netacad-devasc-pc-background.jpg" ]]; then
    install -m 0644 "$ASSETS/netacad-devasc-pc-background.jpg" /opt/netacad-devasc-pc-background.jpg
    # padrão do sistema (vale para qualquer usuário MATE) via dconf
    mkdir -p /etc/dconf/profile /etc/dconf/db/local.d
    [[ -f /etc/dconf/profile/user ]] || printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
    cat > /etc/dconf/db/local.d/00-devasc <<'EOF'
[org/mate/desktop/background]
picture-filename='/opt/netacad-devasc-pc-background.jpg'
picture-options='zoom'
EOF
    dconf update || warn "dconf update falhou (wallpaper)"
  fi
  ok "pylintrc e wallpaper aplicados"
fi

# ------------------------------------------------------------------ 12. GUEST TOOLS
if step guest; then
  info "Ferramentas de integração com o hipervisor ($VIRT)..."
  case "$VIRT" in
    vmware)    apt_install open-vm-tools; [[ $WITH_DESKTOP -eq 1 ]] && apt_install open-vm-tools-desktop ;;
    microsoft) apt_install linux-cloud-tools-virtual linux-tools-virtual || warn "hyperv tools não instalaram" ;;
    kvm|qemu)  apt_install qemu-guest-agent spice-vdagent ;;
    oracle)    info "VirtualBox: instale os Guest Additions pelo menu do VirtualBox, se quiser." ;;
    *)         info "Nenhum hipervisor conhecido detectado." ;;
  esac
  ok "Guest tools verificadas"
fi

# ------------------------------------------------------------------ 13. FIM
if step finish; then
  apt-get autoremove -y >/dev/null
  echo
  echo "=============================================================="
  ok "DEVASC-VM configurada!  ($ARCH, $VIRT)"
  echo "  Usuário: $DEVASC_USER   Senha: a que você escolheu   Hostname: $VM_HOSTNAME"
  echo "  Trocar a senha depois:  passwd"
  echo "  IP(s):   $(hostname -I)"
  echo "  Acesso:  SSH (porta 22) e RDP (porta 3389, sessão Xorg)"
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo; echo -e "${C_WARN}Avisos:${C_0}"; printf '  - %s\n' "${WARNINGS[@]}"
  fi
  echo "  Reinicie a VM:  sudo reboot"
  echo "=============================================================="
fi
