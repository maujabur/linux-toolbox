#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TARGET="$HOME/.config/tmux/tmux.conf"
SOURCE="$REPO_DIR/configs/tmux/tmux.conf"

mkdir -p "$(dirname "$TARGET")"
if [[ -L "$TARGET" ]] && [[ "$(readlink "$TARGET")" == "$SOURCE" ]]; then
  echo "tmux já configurado."
  exit 0
fi
if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  mv -- "$TARGET" "$TARGET.bak.$(date +%Y%m%d_%H%M%S)"
fi
ln -s "$SOURCE" "$TARGET"
echo "Configuração do tmux vinculada: $TARGET"
