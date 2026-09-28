# Notas para o manual do aluno

Itens a incluir no manual/guia do aluno (vão sendo anotados durante o projeto).

## Usuário e senha

- No instalador do Ubuntu, criar o usuário com o nome **`devasc`** (hostname pode ficar qualquer um; o script muda para `labvm`).
- A senha é **escolhida pelo aluno** e o script não altera. Se o script precisar criar o `devasc`, ele pergunta a senha no início.
- Para trocar a senha depois:
  ```
  passwd
  ```
- Onde os roteiros usam `Cisco123!` como senha do `devasc`, usar a própria senha:
  - **Lab 7.4.8** (Ansible + Apache): no arquivo `hosts`, `ansible_ssh_pass=<sua senha>`.
- Continuam valendo as credenciais que **não** são do Linux:
  - School Library API (lab 4.5.5): `cisco` / `Cisco123!` (do próprio simulador).
  - Roteadores/Sandbox: as credenciais informadas no roteiro alternativo.

## Acesso remoto

- RDP: sessão **Xorg**, usuário `devasc` e a sua senha.
- Se o RDP abrir tela preta ou cair: faça logoff da sessão do console da VM (ou instale com `--no-autologin`).

## Hyper-V

- Desmarcar **Inicialização Segura** (Secure Boot) — ver `instalacao-vm.md`.
