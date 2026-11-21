#!/usr/bin/env bash
# No Debian, o executável do pacote fd-find se chama fdfind. Este script
# disponibiliza o nome fd apenas no espaço do usuário, sem sobrescrever nada.
#
# Códigos de saída:
#   0  configurado agora, já estava configurado ou (--dry-run) seria configurado
#   1  erro (por exemplo, fdfind não está instalado)
#   2  conflito: ~/.local/bin/fd já existe e não é um link para fdfind;
#      nada foi alterado e a configuração NÃO foi feita
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$SCRIPT_DIR/lib.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Uso: setup-fd.sh [--dry-run]"
      echo "Cria o link ~/.local/bin/fd para fdfind, sem sobrescrever arquivos existentes."
      echo "Saída 0: configurado ou já configurado. Saída 2: conflito, nada foi alterado."
      exit 0
      ;;
    *) die "Opção desconhecida: $arg" ;;
  esac
done

if ! command -v fdfind >/dev/null 2>&1; then
  die "fdfind não encontrado. Instale o pacote fd-find antes."
fi

BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/fd"
SOURCE="$(command -v fdfind)"

if [[ -L "$TARGET" && "$(readlink -f -- "$TARGET")" == "$(readlink -f -- "$SOURCE")" ]]; then
  MSG=("Já configurado: $TARGET -> $SOURCE" "Nada a fazer: o resultado desta opção já está em vigor.")
elif [[ -e "$TARGET" || -L "$TARGET" ]]; then
  banner err "CONFLITO: $TARGET já existe" \
    "e não é um link para $SOURCE." \
    "Nada foi alterado e o nome fd NÃO foi configurado." \
    "Remova ou renomeie o arquivo e execute novamente."
  exit 2
elif ((DRY_RUN)); then
  [[ -d "$BIN_DIR" ]] || log "[dry-run] Criaria o diretório $BIN_DIR"
  log "[dry-run] Criaria o link $TARGET -> $SOURCE"
  MSG=("[dry-run] Nenhuma alteração foi feita.")
else
  mkdir -p -- "$BIN_DIR"
  ln -s -- "$SOURCE" "$TARGET"
  MSG=("Criado: $TARGET -> $SOURCE")
fi

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  MSG+=("" "ATENÇÃO: $BIN_DIR não está no PATH desta sessão."
    "Adicione-o ao PATH do seu shell para executar fd diretamente.")
fi
banner ok "${MSG[@]}"
