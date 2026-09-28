# Instalação da VM base (antes do devasc-setup.sh)

Base recomendada: **Ubuntu Server 24.04 LTS** (amd64 ou arm64), com OpenSSH marcado na instalação.

Download da ISO:
- Intel e AMD: https://releases.ubuntu.com/24.04/
- ARM (Apple Silicon): https://cdimage.ubuntu.com/ubuntu/releases/24.04.5/release/ (arquivo `ubuntu-24.04.5-live-server-arm64.iso`)

## Hyper-V (Windows, Intel/AMD)

- Geração 2, 4 GB RAM (sem memória dinâmica), 2–4 vCPUs, disco 40 GB, rede no "Default Switch".
- **Segurança: desmarcar "Habilitar Inicialização Segura" (Secure Boot).**
  Testado em 28/09/2026: com o Secure Boot ligado a VM não deu boot com a ISO do Ubuntu.
- Desativar pontos de verificação automáticos.
- No instalador, a placa aparece como `eth0` com DHCP (ex.: 172.19.x.x/20 no Default Switch). Manter o padrão; o script não depende do nome da interface.

## VMware Fusion (Mac Apple Silicon)

- ISO arm64 do Ubuntu Server 24.04.
- (a completar após o teste)

## Histórico de testes

| Data | Plataforma | Base | Resultado |
|---|---|---|---|
| 28/09/2026 | Hyper-V (Intel, amd64) | Ubuntu Server 24.04.5 | ✅ devasc-verify: tudo OK (após copiar `labs/` e `assets/` junto com os scripts) |
