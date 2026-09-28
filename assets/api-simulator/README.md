# devasc-api-simulator (School Library API) — versão adaptada

Original: `/opt/API-SIMULATOR` da DEVASC-VM oficial (baseado em https://github.com/nikolayg/sample-python-api).

Mudanças para Ubuntu 24.04 / Python 3.12 / amd64 e arm64:
- `flask_restplus` → `flask_restx` (fork mantido, mesma API);
- `RESTPLUS_MASK_SWAGGER` → `RESTX_MASK_SWAGGER`;
- `run()` lê `SIM_HOST`/`SIM_PORT` (padrão 192.0.2.1:80), sem `debug=True`;
- escuta direto na porta 80 via systemd (sem a regra de iptables do original).

Instalado pelo `devasc-setup.sh` (etapa `api-simulator`) em `/opt/API-SIMULATOR`, serviço `devasc-api-simulator`.
