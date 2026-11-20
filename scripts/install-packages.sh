#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PROFILE="${1:-base}"
PACKAGE_FILE="$REPO_DIR/packages/$PROFILE.txt"

if [[ ! "$PROFILE" =~ ^[a-z][a-z0-9_-]*$ ]] || [[ ! -f "$PACKAGE_FILE" ]]; then
  echo "Perfil inválido: $PROFILE" >&2
  exit 1
fi
if ! command -v apt-get >/dev/null; then
  echo "Este script exige Debian/Ubuntu com apt-get." >&2
  exit 1
fi
mapfile -t PACKAGES < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$PACKAGE_FILE")
if (("${#PACKAGES[@]}" == 0)); then
  echo "Nenhum pacote listado em $PACKAGE_FILE"
  exit 0
fi
sudo apt-get update
sudo apt-get install -y "${PACKAGES[@]}"

# Ajuste opcional e não destrutivo do nome fd após instalar o perfil agents.
if [[ "$PROFILE" == "agents" ]]; then
  bash "$SCRIPT_DIR/setup-fd.sh"
fi
