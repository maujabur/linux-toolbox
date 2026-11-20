#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_LINE="source \"$REPO_DIR/configs/bash/aliases.sh\""
BASHRC="$HOME/.bashrc"

touch "$BASHRC"
if grep -Fqx "$SOURCE_LINE" "$BASHRC"; then
  echo "Aliases já configurados em $BASHRC"
  exit 0
fi
cp -p "$BASHRC" "$BASHRC.bak.$(date +%Y%m%d_%H%M%S)"
printf '\n# linux-toolbox: aliases pessoais\n%s\n' "$SOURCE_LINE" >> "$BASHRC"
echo "Aliases adicionados. Execute: source ~/.bashrc"
