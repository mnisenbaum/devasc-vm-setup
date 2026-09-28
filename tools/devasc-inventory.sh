#!/usr/bin/env bash
# =============================================================================
# devasc-inventory.sh  -  Inventário da DEVASC-VM (Cisco DevNet Associate)
# -----------------------------------------------------------------------------
# Coleta tudo o que foi instalado/configurado na VM, SOMENTE LEITURA.
# Não altera nada no sistema. Gera um .tar.gz para análise.
#
# Uso (na DEVASC-VM original):
#   chmod +x devasc-inventory.sh
#   sudo ./devasc-inventory.sh              # inventário padrão
#   sudo ./devasc-inventory.sh --with-labs  # inclui cópia de ~/labs (texto < 2 MB)
#
# Privacidade: NÃO copia chaves privadas, /etc/shadow, tokens nem histórico
# de navegação. Senhas não são coletadas.
# =============================================================================
set -u

WITH_LABS=0
[[ "${1:-}" == "--with-labs" ]] && WITH_LABS=1

if [[ $EUID -ne 0 ]]; then
  echo "Rode com sudo:  sudo $0 $*"; exit 1
fi

TUSER="${SUDO_USER:-devasc}"
THOME="$(getent passwd "$TUSER" | cut -d: -f6)"
STAMP="$(date +%Y%m%d-%H%M)"
OUTNAME="devasc-inventory-$(hostname)-$STAMP"
OUT="/tmp/$OUTNAME"
mkdir -p "$OUT"/{system,apt,snap,python,node,other-lang,opt,docker,services,users,home,dotfiles,etc,desktop,network,changes,labs}

log() { echo -e "\e[1;34m[inventário]\e[0m $*"; }
# roda comando e salva saída; nunca aborta o script
run() { local f="$1"; shift; { echo "\$ $*"; timeout 300 bash -c "$*"; } >"$OUT/$f" 2>&1 || true; }
# roda comando como o usuário da VM (devasc)
urun() { local f="$1"; shift; { echo "\$ (como $TUSER) $*"; timeout 120 sudo -u "$TUSER" -H bash -lc "$*" </dev/null; } >"$OUT/$f" 2>&1 || true; }
have() { command -v "$1" >/dev/null 2>&1; }

log "Usuário alvo: $TUSER ($THOME)"

# lista de todos os arquivos que pertencem a algum pacote .deb (para achar "órfãos")
OWNED=/tmp/$OUTNAME-dpkg-owned.txt
cat /var/lib/dpkg/info/*.list 2>/dev/null | sort -u > "$OWNED"
orphans() { sort -u | comm -23 - "$OWNED"; }   # lê caminhos no stdin, devolve os que não são de pacote
export -f orphans; export OWNED

# ---------------------------------------------------------------- SISTEMA
log "Sistema..."
run system/os-release.txt       "cat /etc/os-release; lsb_release -a"
run system/uname.txt            "uname -a; dpkg --print-architecture"
run system/hostnamectl.txt      "hostnamectl"
run system/hardware.txt         "lscpu; free -h; df -hT -x tmpfs -x squashfs; lsblk"
run system/kernel-modules.txt   "lsmod"
run system/locale-tz.txt        "localectl; timedatectl; cat /etc/default/keyboard"
run system/install-date.txt     "ls -la --time-style=full-iso /var/log/installer 2>/dev/null; head -3 /var/log/dpkg.log* 2>/dev/null; stat / | grep -i birth"

# ---------------------------------------------------------------- APT
log "Pacotes apt..."
run apt/manual-packages.txt     "apt-mark showmanual | sort"
run apt/all-packages.tsv        "dpkg-query -W -f='\${Package}\t\${Version}\t\${Architecture}\t\${Status}\n' | sort"
run apt/held-packages.txt       "apt-mark showhold"
run apt/sources.txt             "cat /etc/apt/sources.list; for f in /etc/apt/sources.list.d/*; do echo \"=== \$f\"; cat \"\$f\"; done"
run apt/keyrings.txt            "ls -la /etc/apt/trusted.gpg.d/ /usr/share/keyrings/ /etc/apt/keyrings/ 2>/dev/null"
run apt/local-debs.txt          "apt list --installed 2>/dev/null | grep -E ',local\\]'"   # .deb instalados à mão (fora de repositório)
# Histórico de instalação: o que foi instalado, em que ordem, com que comando
run apt/apt-history.log         "zcat -f /var/log/apt/history.log* 2>/dev/null"
run apt/dpkg-installs.log       "zcat -f /var/log/dpkg.log* 2>/dev/null | grep -E ' (install|remove|purge) '"

# ---------------------------------------------------------------- SNAP / FLATPAK
log "Snap/Flatpak..."
have snap    && run snap/snap-list.txt      "snap list --all"
have snap    && run snap/snap-connections.txt "snap connections"
have flatpak && run snap/flatpak-list.txt   "flatpak list"

# ---------------------------------------------------------------- PYTHON
log "Python (sistema, usuário e venvs)..."
run python/versions.txt         "ls -la /usr/bin/python* /usr/local/bin/python* 2>/dev/null; python3 --version; python3 -m pip --version; update-alternatives --display python 2>/dev/null"
run python/pip-system.txt       "python3 -m pip list --format=freeze 2>/dev/null"
run python/pip-system-local.txt "ls -la /usr/local/lib/python3*/dist-packages 2>/dev/null"
urun python/pip-user.txt        "python3 -m pip list --user --format=freeze 2>/dev/null"
urun python/pyenv-conda.txt     "which pyenv conda pipx poetry 2>/dev/null; pyenv versions 2>/dev/null; pipx list 2>/dev/null; conda env list 2>/dev/null"
# encontra venvs em qualquer lugar (exceto /proc, /snap)
find / -xdev \( -path /proc -o -path /snap -o -path /sys \) -prune -o -name pyvenv.cfg -print 2>/dev/null > "$OUT/python/venvs-found.txt"
i=0
while read -r cfg; do
  vdir="$(dirname "$cfg")"; i=$((i+1))
  { echo "# venv: $vdir"; cat "$cfg"; echo "# ---- pip freeze"; "$vdir/bin/python" -m pip freeze 2>&1; } > "$OUT/python/venv-$i.txt" || true
done < "$OUT/python/venvs-found.txt"
# ferramentas-chave dos labs
urun python/key-tools.txt "for t in ansible ansible-playbook pyats genie netmiko ncclient napalm requests yang pyang robot pytest flask docker-compose git; do printf '%-18s' \$t; (command -v \$t && \$t --version 2>&1 | head -1) || echo '(não encontrado no PATH)'; done; python3 -c 'import ncclient,netmiko,requests; print(\"imports ok\")' 2>&1"

# ---------------------------------------------------------------- NODE / OUTRAS LINGUAGENS
log "Node, Ruby, Go, Java..."
urun node/node.txt              "node -v; npm -v; npm ls -g --depth=0; ls ~/.nvm 2>/dev/null"
urun other-lang/langs.txt       "ruby -v; gem list; go version; java -version 2>&1; javac -version 2>&1; dotnet --info 2>/dev/null | head; php -v 2>/dev/null | head -1"

# ---------------------------------------------------------------- /opt, /usr/local, binários soltos
log "/opt e /usr/local..."
run opt/opt-tree.txt            "find /opt -maxdepth 3 -printf '%M %u %s %TY-%Tm-%Td %p\n' 2>/dev/null"
run opt/opt-sizes.txt           "du -sh /opt/* 2>/dev/null"
run opt/usr-local.txt           "find /usr/local -maxdepth 3 -not -path '*/dist-packages/*' -printf '%M %u %s %TY-%Tm-%Td %p\n' 2>/dev/null"
run opt/packettracer.txt        "ls -la /opt/pt 2>/dev/null; cat /opt/pt/*.txt 2>/dev/null | head -20; dpkg -l | grep -i packet"
run opt/binaries-not-from-dpkg.txt "find /usr/local/bin /usr/local/sbin /opt -maxdepth 2 -type f -executable 2>/dev/null | orphans"

# ---------------------------------------------------------------- DOCKER
log "Docker..."
if have docker; then
  run docker/version.txt        "docker version; docker info"
  run docker/images.txt         "docker images --digests"
  run docker/containers.txt     "docker ps -a --no-trunc"
  run docker/volumes-networks.txt "docker volume ls; docker network ls"
  run docker/inspect-containers.json "docker inspect \$(docker ps -aq) 2>/dev/null"
fi
run docker/compose-files.txt    "find / -xdev \( -path /proc -o -path /snap \) -prune -o \( -name 'docker-compose*.yml' -o -name 'compose*.yaml' -o -name Dockerfile \) -print 2>/dev/null"

# ---------------------------------------------------------------- SERVIÇOS
log "Serviços..."
run services/enabled.txt        "systemctl list-unit-files --state=enabled --no-pager"
run services/running.txt        "systemctl list-units --type=service --state=running --no-pager"
run services/failed.txt         "systemctl --failed --no-pager"
run services/custom-units.txt   "ls -la /etc/systemd/system/ /etc/systemd/system/*.wants 2>/dev/null; for f in /etc/systemd/system/*.service; do echo \"=== \$f\"; cat \"\$f\"; done 2>/dev/null"
run services/timers-cron.txt    "systemctl list-timers --all --no-pager; ls -la /etc/cron.d; cat /etc/crontab; crontab -l -u $TUSER 2>&1; crontab -l 2>&1"
run network/listening.txt       "ss -tulpn"

# ---------------------------------------------------------------- USUÁRIOS
log "Usuários e grupos..."
run users/users.txt             "getent passwd | awk -F: '\$3>=1000 && \$3<65000'"
run users/groups.txt            "id $TUSER; getent group | awk -F: '\$4!=\"\"'"
run users/sudoers.txt           "ls -la /etc/sudoers.d; grep -v '^#' /etc/sudoers | grep -v '^\$'; cat /etc/sudoers.d/* 2>/dev/null"
run users/autologin.txt         "cat /etc/gdm3/custom.conf /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/* 2>/dev/null"

# ---------------------------------------------------------------- HOME DO USUÁRIO
log "Home de $TUSER..."
run home/tree.txt               "find '$THOME' -maxdepth 4 \( -path '*/.cache' -o -path '*/snap/*/common/.cache' -o -path '*/.local/share/Trash' -o -path '*/node_modules' -o -path '*/.git/objects' \) -prune -o -printf '%M %s %TY-%Tm-%Td %p\n' 2>/dev/null"
run home/sizes.txt              "du -sh '$THOME'/* '$THOME'/.[!.]* 2>/dev/null | sort -h"
# dotfiles (seguros)
for f in .bashrc .profile .bash_aliases .bash_logout .gitconfig .vimrc .nanorc .inputrc .tmux.conf .xsessionrc .xsession .pypirc_SKIP .ansible.cfg .netrc_SKIP; do
  [[ "$f" == *_SKIP ]] && continue
  [[ -f "$THOME/$f" ]] && cp "$THOME/$f" "$OUT/dotfiles/" 2>/dev/null
done
[[ -f "$THOME/.ssh/config" ]] && cp "$THOME/.ssh/config" "$OUT/dotfiles/ssh_config"
run dotfiles/ssh-dir-listing.txt "ls -la '$THOME/.ssh' 2>/dev/null"   # só nomes, sem conteúdo das chaves
# VS Code
urun home/vscode-extensions.txt "code --list-extensions --show-versions 2>/dev/null"
[[ -f "$THOME/.config/Code/User/settings.json" ]] && cp "$THOME/.config/Code/User/settings.json" "$OUT/dotfiles/vscode-settings.json"
[[ -f "$THOME/.config/Code/User/keybindings.json" ]] && cp "$THOME/.config/Code/User/keybindings.json" "$OUT/dotfiles/vscode-keybindings.json"
# Postman / Chromium (só metadados e favoritos)
run home/postman.txt            "ls -la /opt/Postman* '$THOME'/Postman* '$THOME'/.config/Postman 2>/dev/null; snap list postman 2>/dev/null"
for b in "$THOME/snap/chromium/common/chromium/Default/Bookmarks" "$THOME/.config/chromium/Default/Bookmarks"; do
  [[ -f "$b" ]] && cp "$b" "$OUT/home/chromium-bookmarks.json"
done
# histórico do bash: revela comandos usados na preparação da VM
[[ -f "$THOME/.bash_history" ]] && cp "$THOME/.bash_history" "$OUT/home/bash_history-$TUSER.txt"
[[ -f /root/.bash_history ]] && cp /root/.bash_history "$OUT/home/bash_history-root.txt"

# ---------------------------------------------------------------- DESKTOP / GUI
log "Desktop..."
run desktop/session.txt         "ls /usr/share/xsessions /usr/share/wayland-sessions; cat /etc/X11/default-display-manager; echo \$XDG_CURRENT_DESKTOP; dpkg -l | grep -E 'xfce|gnome-shell|mate-desktop|lxde|lxqt|kde-plasma|cinnamon|xrdp|xorg' | awk '{print \$2, \$3}'"
mkdir -p "$OUT/desktop/Desktop" "$OUT/desktop/applications" "$OUT/desktop/autostart"
cp "$THOME"/Desktop/* "$OUT/desktop/Desktop/" 2>/dev/null
cp "$THOME"/.local/share/applications/*.desktop "$OUT/desktop/applications/" 2>/dev/null
cp "$THOME"/.config/autostart/* "$OUT/desktop/autostart/" 2>/dev/null
cp /etc/xdg/autostart/*.desktop "$OUT/desktop/autostart/" 2>/dev/null
run desktop/usr-share-apps-custom.txt "ls -1d /usr/share/applications/*.desktop | orphans"
urun desktop/gsettings.txt      "timeout 20 gsettings list-recursively 2>/dev/null | grep -E 'favorite-apps|picture-uri|input-sources|xkb|idle-delay|lock-enabled|theme' "
run desktop/xfconf-files.txt   "find '$THOME'/.config/xfce4 -name '*.xml' 2>/dev/null"
cp -r "$THOME/.config/xfce4" "$OUT/desktop/xfce4-config" 2>/dev/null
run desktop/wallpapers.txt      "ls -la /usr/share/backgrounds '$THOME'/Pictures 2>/dev/null"

# ---------------------------------------------------------------- /etc
log "/etc (arquivos alterados)..."
run etc/dpkg-verify.txt         "dpkg --verify 2>/dev/null"          # conffiles alterados vs pacote
run etc/hosts-env.txt           "cat /etc/hosts /etc/environment /etc/hostname; ls -la /etc/profile.d; cat /etc/profile.d/*.sh 2>/dev/null"
run etc/netplan.txt             "for f in /etc/netplan/*; do echo \"=== \$f\"; cat \"\$f\"; done"
run etc/sysctl.txt              "cat /etc/sysctl.conf /etc/sysctl.d/*.conf 2>/dev/null | grep -v '^#' | grep -v '^\$'"
run etc/ssh-xrdp.txt            "grep -v '^#' /etc/ssh/sshd_config | grep -v '^\$'; cat /etc/xrdp/xrdp.ini 2>/dev/null | head -60"
run etc/orphan-etc-files.txt    "find /etc -xdev -type f 2>/dev/null | orphans | grep -v -E '^/etc/(ssl/certs|alternatives|ld.so.cache|machine-id|shadow|gshadow|passwd|group|subuid|subgid)'"

# ---------------------------------------------------------------- REDE
run network/ip.txt              "ip -br addr; ip route; resolvectl status 2>/dev/null | head -30; nmcli con show 2>/dev/null"

# ---------------------------------------------------------------- MUDANÇAS APÓS INSTALAÇÃO
log "Arquivos criados/alterados após a instalação do SO..."
REF=/var/log/installer
[[ -e $REF ]] || REF=/etc/hostname
for d in /etc /opt /usr/local /usr/share/applications "$THOME"; do
  find "$d" -xdev -newer "$REF" -type f \
    -not -path '*/.cache/*' -not -path '*/snap/*' -not -path '*/.git/*' -not -path '*/node_modules/*' \
    -not -path '*/__pycache__/*' -not -path '*/.local/share/Trash/*' \
    -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' 2>/dev/null
done | sort > "$OUT/changes/files-newer-than-install.txt"

# ---------------------------------------------------------------- LABS
log "Labs..."
run labs/labs-tree.txt          "find '$THOME'/labs -printf '%M %s %TY-%Tm-%Td %p\n' 2>/dev/null"
run labs/git-repos.txt          "find '$THOME' -maxdepth 5 -name .git -type d 2>/dev/null | while read g; do r=\$(dirname \$g); echo \"== \$r\"; git -C \$r remote -v; git -C \$r log -1 --oneline; done"
run labs/requirements-files.txt "find '$THOME' -maxdepth 6 \( -name 'requirements*.txt' -o -name Pipfile -o -name pyproject.toml -o -name package.json \) -not -path '*/node_modules/*' 2>/dev/null | while read f; do echo \"=== \$f\"; cat \"\$f\"; done"
if [[ $WITH_LABS -eq 1 && -d "$THOME/labs" ]]; then
  log "Copiando ~/labs (arquivos de texto < 2 MB)..."
  ( cd "$THOME" && find labs -type f -size -2M -not -path '*/.git/*' -not -path '*/venv/*' -not -path '*/node_modules/*' -print0 \
     | xargs -0 -I{} sh -c 'file -b --mime "{}" | grep -q "charset=binary" || { mkdir -p "'"$OUT"'/labs/copy/$(dirname "{}")"; cp "{}" "'"$OUT"'/labs/copy/{}"; }' )
fi

# ---------------------------------------------------------------- EMPACOTA
log "Empacotando..."
tar -czf "$THOME/$OUTNAME.tar.gz" -C /tmp "$OUTNAME"
chown "$TUSER": "$THOME/$OUTNAME.tar.gz"
rm -rf "$OUT" "$OWNED"
SIZE=$(du -h "$THOME/$OUTNAME.tar.gz" | cut -f1)
echo
log "Pronto!  Arquivo gerado: $THOME/$OUTNAME.tar.gz  ($SIZE)"
log "Envie esse arquivo para análise."
