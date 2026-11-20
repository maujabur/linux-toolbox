#!/usr/bin/env bash
set -euo pipefail

# No Debian, o executável do pacote fd-find se chama fdfind.
# Disponibiliza o nome fd apenas no espaço do usuário, sem sobrescrever arquivos.
if ! command -v fdfind >/dev/null 2>&1; then
  echo "fdfind não encontrado. Instale o pacote fd-find antes." >&2
  exit 1
fi

BIN_DIR="$HOME/.local/bin"
TARGET="$BIN_DIR/fd"
SOURCE="$(command -v fdfind)"
mkdir -p "$BIN_DIR"

if [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$SOURCE" ]]; then
  echo "Alias executável fd já configurado em $TARGET"
elif [[ -e "$TARGET" || -L "$TARGET" ]]; then
  echo "O caminho $TARGET já existe; não foi alterado." >&2
  exit 1
else
  ln -s -- "$SOURCE" "$TARGET"
  echo "Criado: $TARGET -> $SOURCE"
fi

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "Atenção: $BIN_DIR não está no PATH desta sessão."
  echo 'Adicione-o ao PATH do seu shell para executar fd diretamente.'
fi
