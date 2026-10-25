FROM ubuntu:24.04

USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends -y samba && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# smb.conf endurecido: aceita SOMENTE SMB 3.1.1 com criptografia obrigatória
# (AES-128-GCM) e autenticação NTLMv2. Como o SMB cifrado não usa TLS, proxies
# de inspeção SSL/TLS (Netskope e similares) não conseguem interceptá-lo, e
# sniffers de rede veem apenas texto cifrado — nem nomes de arquivos trafegam
# em claro. Observação importante: isto protege só o tráfego de rede. Agentes
# de monitoramento com hooks de filesystem/kernel no HOST (que guarda os
# arquivos em texto claro) ou no CLIENTE ainda os enxergam; para sigilo, guarde
# os arquivos já cifrados em repouso e decifre só em máquina sem esses agentes
COPY smb.txt /etc/samba/smb.conf

# Valida a sintaxe do smb.conf em tempo de build: se houver opção inválida ou
# erro de sintaxe, o build FALHA imediatamente, em vez de subir um serviço
# quebrado ou silenciosamente inseguro
RUN testparm -s > /dev/null

# Usuário dedicado ao compartilhamento, sem shell/login no sistema, em vez de usar root.
# UID 10001 porque a imagem ubuntu:24.04 já traz um usuário padrão "ubuntu" com
# UID 1000, e useradd falha em caso de UID duplicado
RUN useradd --no-create-home --shell /usr/sbin/nologin --uid 10001 smbuser

# Diretório do share criado já na imagem com dono restrito (uid 10001) e modo
# 0770: ao montar um volume do host por cima, basta o diretório do host
# pertencer ao uid 10001; sem volume, o share nasce vazio e inacessível a
# outros usuários do container
RUN mkdir -p /media/shared && \
    chown smbuser:smbuser /media/shared && \
    chmod 0770 /media/shared

# A senha NÃO é gravada na imagem: o entrypoint lê a variável SMB_PASSWORD ao
# iniciar o container e a registra no banco de senhas do Samba (sem hash no layer).
# SMB_UID (opcional, usado em Linux) faz o smbuser assumir o UID do dono da pasta do host
COPY --chmod=0755 samba-entrypoint.sh /usr/local/bin/samba-entrypoint.sh

# Somente a porta SMB sobre TCP (445); 137/138/139 são NetBIOS/SMB1 legado, não
# suportam a criptografia obrigatória e já estão desativadas no próprio smb.conf
# (disable netbios = yes, smb ports = 445), então nem chegam a abrir no container
EXPOSE 445
# O entrypoint define a senha e roda o smbd em foreground, sem depender de
# systemd/systemctl, o que evitaria a necessidade de container --privileged
ENTRYPOINT ["/usr/local/bin/samba-entrypoint.sh"]

# To build this image use this command:
# docker build -t my-samba-server:1.0 -f samba.dockerfile .

# Os scripts samba-start.sh/.ps1 e samba-stop.sh/.ps1 já fazem o run abaixo.
# To run this image use (a senha vai por -e SMB_PASSWORD, herdada do shell; em Linux passe também -e SMB_UID=$(id -u)):
# O formato do -v é  -v <CAMINHO_NO_HOST>:<CAMINHO_NO_CONTAINER>[:ro]
#   /caminho/especifico  = pasta do HOST (sua máquina) que será compartilhada
#                          (no Windows, ex.: D:/pasta ou C:/Users/voce/pasta)
#   /media/shared        = pasta DENTRO do container, é o "path" do [SHARED_FOLDER]
#                          no smb.conf, ou seja, o que o cliente SMB enxerga
#   :ro                  = opcional; monta como somente leitura
# Caso 1 - leitura e escrita nos dois sentidos (host <-> cliente):
# SMB_PASSWORD='sua-senha' docker run -d --name samba -p 445:445 -e SMB_PASSWORD -v /caminho/especifico:/media/shared my-samba-server:1.0
# Caso 2 - somente cópia do host para o cliente (cliente só lê; escrita é recusada):
# SMB_PASSWORD='sua-senha' docker run -d --name samba -p 445:445 -e SMB_PASSWORD -v /caminho/especifico:/media/shared:ro my-samba-server:1.0