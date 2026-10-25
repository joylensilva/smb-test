#!/usr/bin/env bash
# Para e remove o container Samba (Linux e macOS). Execute com: bash samba-stop.sh
# Variavel opcional: SAMBA_CONTAINER (padrao: samba)
set -eu

SAMBA_CONTAINER="${SAMBA_CONTAINER:-samba}"

command -v docker >/dev/null 2>&1 || { echo "Erro: docker nao encontrado no PATH." >&2; exit 1; }

if ! docker container inspect "$SAMBA_CONTAINER" >/dev/null 2>&1; then
    echo "Container '$SAMBA_CONTAINER' nao existe; nada a fazer."
    exit 0
fi

docker stop "$SAMBA_CONTAINER" >/dev/null
docker rm "$SAMBA_CONTAINER" >/dev/null
echo "Container '$SAMBA_CONTAINER' parado e removido."
