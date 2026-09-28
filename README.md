# devasc-vm-setup

Transforma um **Ubuntu 24.04 recém-instalado** numa **DEVASC-VM**, o ambiente de laboratório do curso **Cisco NetAcad DevNet Associate (DEVASC)**.

Funciona em **Intel/AMD (amd64)** e **ARM (arm64, ex.: Mac Apple Silicon)**, em Hyper-V, VMware (Workstation/Fusion), VirtualBox, UTM etc.

> Projeto independente da ABRedes para facilitar a vida de alunos e instrutores. Não é um produto oficial da Cisco.

## Instalação rápida

Tudo é feito **dentro da VM**: não é preciso copiar nada do seu computador.

**1. Crie a VM** com **Ubuntu Server 24.04 LTS** (4 GB de RAM, 2–4 vCPUs, 40 GB de disco).
No instalador do Ubuntu:
- crie o usuário **`devasc`** (a senha você escolhe);
- marque **Install OpenSSH server**.

Detalhes por hipervisor (Hyper-V, VMware, VirtualBox, UTM): [`docs/instalacao-vm.md`](docs/instalacao-vm.md).

**2. Entre na VM** como `devasc` (pelo console ou por SSH) e rode:

```bash
git clone https://github.com/mnisenbaum/devasc-vm-setup.git
cd devasc-vm-setup
sudo ./devasc-setup.sh
```

A instalação leva de 20 a 40 minutos, dependendo da internet. No fim, reinicie:

```bash
sudo reboot
```

**3. Confira** (de novo como `devasc`, **sem** sudo):

```bash
~/devasc-vm-setup/devasc-verify.sh
```

Tudo com ✔ = VM pronta para os labs. 🎉

> Se aparecer `git: command not found`, instale antes com `sudo apt update && sudo apt install -y git`.

## O que é instalado

| Item | Detalhe |
|---|---|
| Desktop | MATE + LightDM (igual à DEVASC-VM original) + **xrdp** (acesso por Área de Trabalho Remota) |
| Usuário | `devasc` (uid 900), sudo sem senha, hostname `labvm` — o prompt fica `devasc@labvm` como nos roteiros |
| Python | venv global em `/opt/devasc/venv`, ativado no `.bashrc`: requests, Faker, PyYAML, xmltodict, Flask, pyotp, ncclient, pyang, netmiko, Ansible + `cisco.ios`, pyATS/Genie, webexteamssdk… |
| Ferramentas | Docker CE, VS Code (+ extensão Python), Chromium, draw.io, git, net-tools, dnsutils, traceroute, sshpass, tcpdump, sqlite3… |
| Rede dos labs | interface `dummy0` com 192.0.2.1–5 (usada no lab 7.4.8) |
| School Library API | simulador do lab 4.5.5 em `http://library.demo.local` (login `cisco` / `Cisco123!`) |
| Labs | `~/labs/devnet-src` |

**Não** fazem parte da VM: Packet Tracer e Postman/Bruno (rodam no computador do aluno) e o roteador CSR1000v (substituído pelo DevNet Sandbox).

## Opções

```bash
sudo ./devasc-setup.sh --no-desktop        # sem MATE/xrdp (uso só por SSH / VS Code Remote)
sudo ./devasc-setup.sh --no-autologin      # sem login automático (recomendado para quem usa RDP)
sudo ./devasc-setup.sh --no-api-simulator  # sem o School Library API
sudo ./devasc-setup.sh --only labs         # roda só uma etapa
```

Etapas: `check base desktop xrdp tools docker gui-apps user network api-simulator venv labs desktop-icons branding guest finish`.
O script pode ser executado de novo sem problemas. Log em `/var/log/devasc-setup.log`.

## Senha

A senha do `devasc` é a que você escolheu na instalação do Ubuntu (o script não altera). Para trocar: `passwd`.
Nos roteiros que usam `Cisco123!` como senha do Linux (ex.: arquivo `hosts` do lab 7.4.8), use a sua senha.

## Acesso remoto (RDP)

Área de Trabalho Remota → IP da VM → sessão **Xorg** → usuário `devasc`.
Se aparecer tela preta, faça logoff da sessão aberta no console da VM (ou instale com `--no-autologin`).

## Estrutura

```
devasc-setup.sh      instalação
devasc-verify.sh     verificação pós-instalação
labs/devnet-src/     arquivos dos laboratórios (copiados para ~/labs)
assets/              School Library API, wallpaper, .pylintrc
docs/                instalação por hipervisor, matriz labs × dependências, notas para o manual do aluno
tools/               devasc-inventory.sh (inventário de uma DEVASC-VM original)
```

## Créditos

- Scripts e documentação: Moises — [ABRedes](https://abredes.com.br). Licença MIT.
- Arquivos dos labs, School Library API e wallpaper: Cisco Systems, Inc. / Cisco Networking Academy (DEVASC VM). O School Library API foi adaptado para Python 3.12 (flask-restplus → flask-restx); ver [`assets/api-simulator/README.md`](assets/api-simulator/README.md).
