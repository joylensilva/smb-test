# Servidor Samba (SMB) com criptografia obrigatória

Imagem Docker de um servidor Samba que **só aceita SMB 3.1.1 com criptografia obrigatória**. Todo o tráfego de arquivos entre cliente e servidor é cifrado (AES-128-GCM).

## Arquivos

| Arquivo | Função |
|---|---|
| `samba.dockerfile` | Define a imagem (Ubuntu 24.04 + Samba) |
| `smb.txt` | Configuração do Samba (vira `/etc/samba/smb.conf` na imagem) |
| `samba-entrypoint.sh` | Define a senha do usuário ao iniciar o container e executa o `smbd` |
| `samba-start.sh` / `samba-stop.sh` | Subir/parar o servidor no Linux e macOS |
| `samba-start.ps1` / `samba-stop.ps1` | Subir/parar o servidor no Windows |

`openssh.dockerfile`, `samba - Copy.dockerfile`, `smb (cópia).txt` e `smb.txt.bkp` são arquivos antigos e não fazem parte desta configuração.

## Requisitos

- Docker (Docker Desktop no Windows e macOS).
- Cliente SMB com suporte a SMB 3.1.1 e criptografia: Windows 10+, macOS 10.12+ ou `smbclient` moderno.

## Uso rápido

**Linux / macOS**

```bash
bash samba-start.sh
bash samba-stop.sh
```

**Windows (PowerShell)**

```powershell
powershell -ExecutionPolicy Bypass -File .\samba-start.ps1
powershell -ExecutionPolicy Bypass -File .\samba-stop.ps1
```

O start constrói a imagem se ela ainda não existir, sobe o container e mostra como acessar. Se `SAMBA_PASSWORD` não estiver definida, o script gera uma senha aleatória de 12 caracteres (maiúsculas, minúsculas, números e símbolos) e a imprime no console. Anote-a: ela não é salva em lugar nenhum.

Acesso ao compartilhamento: `\\<ip-do-host>\SHARED_FOLDER`, usuário `smbuser`.

## Variáveis de ambiente

Todas são opcionais e valem para os scripts de start. Defina-as no shell antes de executar.

| Variável | Padrão | Descrição |
|---|---|---|
| `SAMBA_HOST_DIR` | Home do usuário (`$HOME` / `%USERPROFILE%`) | Pasta do host a compartilhar |
| `SAMBA_PASSWORD` | Gerada aleatoriamente e exibida | Senha do `smbuser` |
| `SAMBA_PORT` | `445` | Porta publicada no host |
| `SAMBA_READ_ONLY` | `0` | `1` monta a pasta como somente leitura |
| `SAMBA_IMAGE` | `my-samba-server:1.0` | Nome da imagem |
| `SAMBA_CONTAINER` | `samba` | Nome do container (também usado pelo stop) |

Exemplos:

```bash
# Linux/macOS: pasta específica, senha própria, somente leitura
SAMBA_HOST_DIR=/dados/compartilhado SAMBA_PASSWORD='minha-senha' SAMBA_READ_ONLY=1 bash samba-start.sh
```

```powershell
# Windows
$env:SAMBA_HOST_DIR = 'D:\compartilhado'
$env:SAMBA_PORT = '4450'
.\samba-start.ps1
```

## Modos de compartilhamento

- **Leitura e escrita (padrão):** cliente e host trocam arquivos nos dois sentidos.
- **Somente leitura (`SAMBA_READ_ONLY=1`):** o cliente só copia arquivos do host; qualquer escrita é recusada.

## Uso manual (sem os scripts)

```bash
docker build -t my-samba-server:1.0 -f samba.dockerfile .

# Formato do volume: -v <PASTA_NO_HOST>:/media/shared[:ro]
#   /media/shared é o path do [SHARED_FOLDER] no smb.conf (o que o cliente enxerga)
SMB_PASSWORD='sua-senha' docker run -d --name samba -p 445:445 \
  -e SMB_PASSWORD -v /caminho/no/host:/media/shared my-samba-server:1.0
```

Use `-e SMB_PASSWORD` sem valor para o Docker herdar a variável do shell, evitando expor a senha na linha de comando. No Linux, acrescente `-e SMB_UID=$(id -u)` para o `smbuser` poder escrever na pasta do host.

## Como a segurança funciona

Configurada em `smb.txt` (cada diretiva está comentada no arquivo):

- `server min protocol = SMB3_11`: recusa SMB1, SMB2 e SMB 3.0. O 3.1.1 tem *pre-authentication integrity*, que impede downgrade durante a negociação.
- `smb encrypt = required` (global e no share): clientes que não negociarem criptografia são recusados.
- `ntlm auth = ntlmv2-only`: sem NTLMv1, que é quebrável offline.
- `disable netbios = yes` e `smb ports = 445`: sem as portas legadas 137/138/139.
- Spool de impressão desativado, acesso anônimo e guest negados, apenas o usuário `smbuser` acessa.
- A senha é definida na inicialização do container; o hash dela **não** fica gravado na imagem.

## Limitações

- A criptografia protege **somente o tráfego de rede**; os arquivos ficam em texto claro no disco do host.
- No Windows, a porta 445 normalmente já está em uso pelo próprio sistema; use `SAMBA_PORT` com outro valor. Clientes Windows só conectam em portas diferentes da 445 em versões recentes (verifique o suporte a `net use /TCPPORT` na sua versão).
- A senha gerada fica visível no console e no `docker inspect` do container para quem tem acesso ao Docker do host.
- Em Linux, o `smbuser` assume o UID do usuário que executa o script (`SMB_UID`); em Docker Desktop (Windows/macOS) as permissões do bind mount são emuladas e isso não é necessário.

## Verificar a criptografia

Com o container em execução e um cliente conectado:

```bash
docker exec samba smbstatus -b
```

A coluna `Protocol Version` deve mostrar `SMB3_11` e `Encryption` deve mostrar `AES-128-GCM`.
