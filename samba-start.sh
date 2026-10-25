#!/usr/bin/env bash
# Sobe o container Samba (Linux e macOS). Execute com: bash samba-start.sh
#
# Variaveis de ambiente (todas opcionais):
#   SAMBA_HOST_DIR   pasta do host a compartilhar            (padrao: $HOME do usuario)
#   SAMBA_PASSWORD   senha do usuario smbuser                (padrao: gera 12 caracteres aleatorios e exibe)
#   SAMBA_PORT       porta SMB publicada no host             (padrao: 445)
#   SAMBA_READ_ONLY  1 = cliente so le (monta com :ro)       (padrao: 0, leitura e escrita)
#   SAMBA_IMAGE      nome da imagem                          (padrao: my-samba-server:1.0)
#   SAMBA_CONTAINER  nome do container                       (padrao: samba)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAMBA_HOST_DIR="${SAMBA_HOST_DIR:-$HOME}"
SAMBA_PORT="${SAMBA_PORT:-445}"
SAMBA_READ_ONLY="${SAMBA_READ_ONLY:-0}"
SAMBA_IMAGE="${SAMBA_IMAGE:-my-samba-server:1.0}"
SAMBA_CONTAINER="${SAMBA_CONTAINER:-samba}"

command -v docker >/dev/null 2>&1 || { echo "Erro: docker nao encontrado no PATH." >&2; exit 1; }
[ -d "$SAMBA_HOST_DIR" ] || { echo "Erro: pasta '$SAMBA_HOST_DIR' nao existe (SAMBA_HOST_DIR)." >&2; exit 1; }
SAMBA_HOST_DIR="$(cd "$SAMBA_HOST_DIR" && pwd)"

if docker container inspect "$SAMBA_CONTAINER" >/dev/null 2>&1; then
    echo "Erro: o container '$SAMBA_CONTAINER' ja existe. Execute samba-stop.sh antes." >&2
    exit 1
fi

# 12 caracteres; repete ate conter maiuscula, minuscula, numero e simbolo
generate_password() {
    local charset='A-Za-z0-9!@#%^*_+=-' symbols='!@#%^*_+=-' pw
    while :; do
        pw="$(LC_ALL=C tr -dc "$charset" </dev/urandom 2>/dev/null | head -c 12)"
        if [ "${#pw}" -eq 12 ] \
            && [ -n "$(printf '%s' "$pw" | LC_ALL=C tr -dc 'A-Z')" ] \
            && [ -n "$(printf '%s' "$pw" | LC_ALL=C tr -dc 'a-z')" ] \
            && [ -n "$(printf '%s' "$pw" | LC_ALL=C tr -dc '0-9')" ] \
            && [ -n "$(printf '%s' "$pw" | LC_ALL=C tr -dc "$symbols")" ]; then
            printf '%s' "$pw"
            return
        fi
    done
}

GENERATED=0
if [ -z "${SAMBA_PASSWORD:-}" ]; then
    SAMBA_PASSWORD="$(generate_password)"
    GENERATED=1
fi

if ! docker image inspect "$SAMBA_IMAGE" >/dev/null 2>&1; then
    echo "Imagem '$SAMBA_IMAGE' nao encontrada; construindo..."
    docker build -t "$SAMBA_IMAGE" -f "$SCRIPT_DIR/samba.dockerfile" "$SCRIPT_DIR"
fi

MOUNT="$SAMBA_HOST_DIR:/media/shared"
if [ "$SAMBA_READ_ONLY" = "1" ]; then
    MOUNT="$MOUNT:ro"
fi

# Em Linux o smbuser assume o UID do usuario atual para conseguir escrever na pasta do host
SMB_UID_VALUE=""
if [ "$(uname -s)" = "Linux" ]; then
    SMB_UID_VALUE="$(id -u)"
fi

# A senha vai so no ambiente do processo docker (-e sem valor herda), nunca na linha de comando
SMB_PASSWORD="$SAMBA_PASSWORD" docker run -d --name "$SAMBA_CONTAINER" \
    -p "$SAMBA_PORT:445" \
    -v "$MOUNT" \
    -e SMB_PASSWORD \
    -e SMB_UID="$SMB_UID_VALUE" \
    "$SAMBA_IMAGE" >/dev/null

sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' "$SAMBA_CONTAINER" 2>/dev/null)" != "true" ]; then
    echo "Erro: o container nao permaneceu em execucao. Logs:" >&2
    docker logs "$SAMBA_CONTAINER" >&2 || true
    docker rm -f "$SAMBA_CONTAINER" >/dev/null 2>&1 || true
    exit 1
fi

MODE="leitura e escrita"
[ "$SAMBA_READ_ONLY" = "1" ] && MODE="somente leitura (:ro)"

echo "Samba em execucao."
echo "  Share:   //<ip-do-host>/SHARED_FOLDER (porta $SAMBA_PORT)"
echo "  Usuario: smbuser"
echo "  Pasta:   $SAMBA_HOST_DIR ($MODE)"
if [ "$GENERATED" = "1" ]; then
    echo "  Senha gerada: $SAMBA_PASSWORD"
fi
