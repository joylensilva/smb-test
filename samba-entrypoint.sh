#!/bin/sh
set -eu

: "${SMB_PASSWORD:?SMB_PASSWORD nao definida}"

# Em Linux o smbuser assume o UID do dono da pasta do host, senao a escrita no bind mount e negada
if [ -n "${SMB_UID:-}" ]; then
    usermod -o -u "$SMB_UID" smbuser
fi

printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -sa smbuser

# Evita que a senha fique no ambiente do processo smbd (/proc/<pid>/environ)
unset SMB_PASSWORD
exec /usr/sbin/smbd --foreground --no-process-group
