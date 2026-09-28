#!/usr/bin/env bash
# =============================================================================
# devasc-verify.sh - Confere se a DEVASC-VM está pronta para os labs
# Uso (como devasc, sem sudo):   ./devasc-verify.sh
# =============================================================================
VENV_DIR="/opt/devasc/venv"
PASS=0; FAIL=0
ok()  { echo -e "  \e[32m✔\e[0m $1"; PASS=$((PASS+1)); }
bad() { echo -e "  \e[31m✘\e[0m $1"; FAIL=$((FAIL+1)); }
chk() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }

[ -f "$VENV_DIR/bin/activate" ] && . "$VENV_DIR/bin/activate"

echo "== Sistema ($(dpkg --print-architecture), $(. /etc/os-release; echo "$PRETTY_NAME"))"
chk "usuário é devasc"                     test "$(whoami)" = devasc
chk "hostname labvm"                        test "$(hostname)" = labvm
chk "internet (HTTPS)"                      curl -fsS --max-time 10 -o /dev/null https://developer.cisco.com
chk "SSH ativo"                             systemctl is-active --quiet ssh
chk "xrdp ativo"                            systemctl is-active --quiet xrdp
chk "sessão MATE instalada"                 test -f /usr/share/xsessions/mate.desktop

chk "sudo sem senha"                        sudo -n true
chk "dummy0 com 192.0.2.3 (lab 7.4.8)"      bash -c 'ip -br addr show dummy0 | grep -q 192.0.2.3'
read -rsp "Senha do devasc (para testar o SSH do lab 7.4.8; Enter pula): " DPASS; echo
if [ -n "$DPASS" ]; then
  chk "SSH com senha em 192.0.2.3 (lab 7.4.8)" sshpass -p "$DPASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 devasc@192.0.2.3 true
fi

chk "School Library API (lab 4.5.5)"       curl -fsS --max-time 5 -o /dev/null http://library.demo.local/api/v1/books

echo "== Ferramentas"
for c in git vim nano curl wget ifconfig nslookup traceroute ping telnet tcpdump sshpass sqlite3 code chromium drawio; do
  chk "$c" command -v "$c"
done

echo "== Docker"
chk "docker sem sudo (grupo docker)"        docker ps
chk "docker run hello-world"                docker run --rm hello-world

echo "== Python (venv global)"
chk "venv ativo em $VENV_DIR"               test "$VIRTUAL_ENV" = "$VENV_DIR"
chk "python3 -m venv funciona (lab 3.1.12)" bash -c 'd=$(mktemp -d); python3 -m venv "$d/t" && rm -rf "$d"'
for m in requests faker yaml xmltodict flask pyotp OpenSSL ncclient netmiko webexteamssdk; do
  chk "import $m"                           python3 -c "import $m"
done
chk "pyang"                                 pyang -v
chk "ansible + cisco.ios (lab 7.4.7)"       bash -c 'ansible-galaxy collection list 2>/dev/null | grep -q cisco.ios'
chk "pyATS/Genie (lab 7.6.3)"               bash -c 'pyats version check && python3 -c "import genie"'

echo "== Labs"
chk "labs em ~/labs/devnet-src"             test -d "$HOME/labs/devnet-src/parsing"
chk "git init.defaultBranch=master"         test "$(git config --global init.defaultBranch)" = master

echo
echo "Resultado: $PASS ok, $FAIL falha(s)"
[ "$FAIL" -eq 0 ]
