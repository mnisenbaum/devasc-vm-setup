# Matriz Labs × Dependências — DEVASC-VM → Ubuntu 24.04 (amd64/arm64)

> Rascunho v0.1 (28/09/2026), feito a partir dos roteiros ILM e dos arquivos em `pacotes-originais/` e `labs-originais/`.
> Vai ser completado com o resultado do `devasc-inventory.sh`.

## 0. Decisões tomadas (28/09/2026)

- Desktop **MATE** mantido (igual à VM original).
- Python: **venv global** em `/opt/devasc/venv`, ativado no `.bashrc`.
- **Sem ferramentas de IA** na VM.
- **Packet Tracer fora da VM** (roda no host).
- **Postman/Bruno no host**, não na VM.
- **4.5.5**: School Library Simulator substituído pelo demo online do Swagger (Petstore) → roteiro alternativo.
- **CSR1000v → DevNet Sandbox** (Catalyst 8000v/9000) → roteiros alternativos para 7.0.3, 7.4.7, 7.6.3, 8.3.6, 8.3.7.
- **8.8.3**: provavelmente inviável com PT no host — checar se o PT padrão tem "Access Enabled" externo no Network Controller.
- **6.3.6 (Jenkins)** e **7.6.3 (pyATS)**: validar em testes amd64 e arm64.

## 1. Como é a DEVASC-VM original

| Item | Valor original | Proposta para o novo script |
|---|---|---|
| SO | Ubuntu **MATE** 20.04 (focal), amd64 | Ubuntu 24.04 LTS (amd64 e arm64) |
| Desktop / login | MATE + LightDM, sessão X11 | MATE (`ubuntu-mate-desktop` ou `mate-desktop-environment`) + xrdp |
| Usuário | `devasc` (uid 900), senha `Cisco123!` | igual (o script cria/ajusta) |
| Hostname | `labvm` (prompt `devasc@labvm` nos roteiros) | `labvm` |
| Python | 3.8 do sistema + pacotes em `~/.local` (pip --user) | 3.12 do sistema + **um venv global** ativado no `.bashrc` (evita `--break-system-packages`) |
| Ansible | 2.9 via apt | ansible atual (pipx) + collection `cisco.ios` |
| Docker | `docker.io` (apt) | Docker CE do repositório oficial (amd64/arm64) |
| Snaps | chromium, code, postman, drawio | chromium, code, postman, drawio (todos têm arm64 — confirmar postman) |
| VS Code | extensão `ms-python.python` | igual |
| Packet Tracer | `/opt/pt` (`PT7HOME`) | **fora da VM** (roda no host) |
| Outros apt | net-tools, inetutils-traceroute, dnsutils, sshpass, telnet, tcpdump, ftp, vim, sqlitebrowser, openssh-server | igual |
| Pastas | `~/labs/devnet-src/...` | copiar de `labs-originais/devnet-src` |

## 2. Matriz por laboratório

Legenda: ✅ sem problema previsto · ⚠️ precisa adaptação · ❌ bloqueio no ARM

| Lab | O que usa | amd64 | arm64 | Observações |
|---|---|---|---|---|
| 1.1.2 Install the VM | VirtualBox, Chromium, VS Code, Postman | ⚠️ | ⚠️ | Substituído pelo nosso guia (Hyper-V / Fusion) |
| 1.2.2 Linux Review | ls, grep, ip, ping, apt, `man`, passwd | ✅ | ✅ | Precisa de `~/Documents`, `~/labs`; saídas mostram focal (normal) |
| 1.3.3 Python Review | python3, VS Code + ms-python | ✅ | ✅ | `python3 -V` mostrará 3.12 |
| 2.2.7 DevNet Resources | navegador | ✅ | ✅ | |
| 3.1.12 Python Dev Tools | python3-venv, pip | ✅ | ✅ | Roteiro usa `python3 -m pip freeze` no sistema — o venv global muda essa saída (aceitável) |
| 3.3.11 Git | git, vim, conta GitHub (PAT) | ✅ | ✅ | branch padrão: configurar `init.defaultBranch=master` para bater com o roteiro |
| 3.4.6 Python Classes | python3 | ✅ | ✅ | |
| 3.5.7 Unit Test | python3 unittest, `~/labs/devnet-src/unittest` | ✅ | ✅ | |
| 3.6.6 Parsing | json, xml, **PyYAML**, `~/labs/devnet-src/parsing` | ✅ | ✅ | |
| **4.5.5 REST API Simulator** | **School Library API em `http://library.demo.local`** (login cisco / Cisco123!), Postman, curl, **Faker**, requests | ⚠️ | ⚠️ | **Serviço local da VM — descobrir no inventário como roda (container? app em /opt? /etc/hosts?)** |
| 4.9.2 REST API em Python | requests, internet, chave Graphhopper | ✅ | ✅ | |
| 5.6.7 Troubleshooting Tools | ifconfig (net-tools), nslookup (dnsutils), traceroute, ping | ✅ | ✅ | instalar `net-tools dnsutils inetutils-traceroute` |
| 6.2.7 Docker Web App | docker, Flask, curl, bridge 172.17.0.1, imagem `python` | ✅ | ✅ | imagem `python` é multi-arch |
| 6.3.6 Jenkins CI/CD | docker, `jenkins/jenkins:lts`, monta `$(which docker)` e o socket no container, git/GitHub | ⚠️ | ⚠️ | Montar o binário do host no container: funciona melhor com o CLI **estático** do Docker CE. Testar nas duas arquiteturas |
| 6.5.10 Password Evolution | Flask (HTTPS adhoc → `cryptography`/pyOpenSSL), **pyotp**, sqlite3, nohup | ✅ | ✅ | |
| 7.0.3 CSR1000v | VM CSR1000v separada, rede host-only 192.168.56.0/24 | ⚠️ | ❌ | CSR1000v é só x86. **No Mac ARM não roda** → usar DevNet Sandbox (Catalyst 8000v always-on) ou CML. No Hyper-V a rede host-only precisa de switch interno |
| 7.4.7 Ansible + CSR1kv | ansible, `cisco.ios`, paramiko/pylibssh, CSR1kv | ⚠️ | ⚠️ | Playbooks de 2020 (ansible 2.9) — verificar módulos `ios_command`/`ios_config` no ansible atual |
| 7.4.8 Ansible + Apache | ansible, sshpass, openssh-server, apache2 (instalado pelo playbook), SSH com senha para a própria VM | ✅ | ✅ | `PasswordAuthentication yes` no sshd; `host_key_checking=False` |
| 7.6.3 pyATS/Genie | venv + `pyats[full]`, git clone examples, CSR1kv | ⚠️ | ⚠️ | Checar wheels de pyATS para aarch64 e Python 3.12 |
| 8.3.5 YANG | pyang, wget | ✅ | ✅ | |
| 8.3.6 NETCONF | ncclient, xmltodict, ssh porta 830, CSR1kv | ✅ | ⚠️ | depende do alvo (CSR/sandbox) |
| 8.3.7 RESTCONF | requests, Postman, CSR1kv | ✅ | ⚠️ | idem |
| 8.6.7 Webex | requests, conta Webex | ✅ | ✅ | |
| 5.4.6 / 5.5.7 / 5.6.6 / 8.8.2 (PT) | Packet Tracer | — | — | rodam no host |
| 8.8.3 PT + REST | Postman e Python **na VM** falando com o PT Controller em `localhost:58000` | ⚠️ | ⚠️ | Com o PT no host, trocar `localhost` pelo **IP do host visto da VM** (e liberar a porta 58000 no firewall do host). Documentar para o aluno |

## 3. Achados do inventário (VM original, 28/09/2026)

| Achado | Onde | Tratamento no script |
|---|---|---|
| Interface **dummy0** com 192.0.2.1–5/32 | `/etc/netplan/01-netcfg.yaml` | etapa `network` (serviço `devasc-dummy0`). **Necessária no lab 7.4.8** (Ansible usa 192.0.2.3 = a própria VM) |
| `/etc/hosts`: `127.0.1.1 labvm.vm labvm`, `192.0.2.1 library.demo.local`, `192.0.2.2 pt-controller.demo.local` | `/etc/hosts` | hostname replicado; entradas library/pt-controller não (Swagger online / PT no host) |
| **School Library API Simulator** = app Flask em `/opt/API-SIMULATOR` (venv próprio, escuta em 192.0.2.1) iniciado por `/etc/rc.local` | `/opt/API-SIMULATOR`, `rc.local` | **portado** para Python 3.12 (flask-restplus → flask-restx, 3 linhas); testado: GET/POST/DELETE, login, Swagger UI e o `add100RandomBooks.py`. Etapa `api-simulator` (desliga com `--no-api-simulator`) |
| **PT com acesso externo via stunnel** (`/etc/stunnel/pt-controller.demo.local.*`, cert em `/usr/local/share/ca-certificates`) | `/etc/stunnel` | stunnel só adiciona TLS: `pt-controller.demo.local:443 → localhost:58000`. Ou seja, o **PT padrão já escuta na 58000**; com PT no host, a VM talvez alcance `IP_do_host:58000` (testar) |
| `devasc ALL=(ALL) NOPASSWD: ALL` | `/etc/sudoers` | replicado em `/etc/sudoers.d/90-devasc` |
| Autologin do `devasc` no LightDM | `/etc/lightdm/lightdm.conf.d/10-devasc-user.conf` | replicado (desliga com `--no-autologin`) |
| uid/gid 900 | `/etc/passwd` | replicado |
| `.gitconfig`: NetAcad DEVASC / changeme@example.com | `~/.gitconfig` | replicado |
| VS Code: zoom 2, sem auto-update | `settings.json` | replicado |
| Atalhos: Terminal, VS Code, Chromium, draw.io, labs (Link), Keyboard, DPI Scaling (`xrandr --scale 0.8`), Postman, PT | `~/Desktop` | replicados, exceto Postman e PT |
| Scripts Cisco: `cisco-eula.service` (/EULA), `bootup-devasc-message`, `devasc-vm-update` | `/etc/systemd`, `/usr/local/bin` | não replicados (específicos da VM oficial) |
| Wallpaper `/opt/netacad-devasc-pc-background.jpg`, `~/.pylintrc` | `assets/` | etapa `branding` |
| Docker sem imagens pré-baixadas | | nada a fazer |
| `~/labs` igual a `labs-originais/devnet-src` | | ok |

## 4. Pendências (dependem do inventário)

1. Como o **School Library API Simulator** (`library.demo.local`) está implementado e como iniciar.
2. Lista completa de atalhos do desktop e o ícone "DPI Scanning".
3. Arquivos em `/etc` alterados (hosts, sshd, lightdm, sudoers).
4. Conteúdo real de `~/labs` na VM (comparar com `labs-originais/`).
5. Imagens Docker pré-baixadas (a lista antiga veio vazia — talvez coletada sem sudo).
