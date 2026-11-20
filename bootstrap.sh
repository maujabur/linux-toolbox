#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "linux-toolbox"
echo "1) Configurar aliases do Bash"
echo "2) Configurar tmux"
echo "3) Instalar pacotes base"
echo "4) Instalar pacotes de desenvolvimento"
echo "5) Instalar pacotes de desktop"
echo "6) Instalar ferramentas para agentes"
echo "0) Sair"
read -r -p "Escolha: " choice
case "$choice" in
  1) bash "$SCRIPT_DIR/scripts/setup-bash.sh" ;;
  2) bash "$SCRIPT_DIR/scripts/setup-tmux.sh" ;;
  3) bash "$SCRIPT_DIR/scripts/install-packages.sh" base ;;
  4) bash "$SCRIPT_DIR/scripts/install-packages.sh" development ;;
  5) bash "$SCRIPT_DIR/scripts/install-packages.sh" desktop ;;
  6) bash "$SCRIPT_DIR/scripts/install-packages.sh" agents ;;
  0) exit 0 ;;
  *)
    echo "Opção inválida." >&2
    exit 1
    ;;
esac
