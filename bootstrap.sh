#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DRY_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_ARGS=(--dry-run) ;;
    -h | --help)
      echo "Uso: bootstrap.sh [--dry-run]"
      echo "Menu interativo. Nada é alterado sem a sua seleção."
      echo "Com --dry-run, as opções apenas mostram o que seria feito."
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $arg" >&2
      exit 1
      ;;
  esac
done

menu() {
  echo
  echo "linux-toolbox${DRY_ARGS[*]:+ (dry-run)}"
  echo "1) Configurar aliases do Bash"
  echo "2) Configurar tmux"
  echo "3) Instalar pacotes base (usa sudo)"
  echo "4) Instalar pacotes de desenvolvimento (usa sudo)"
  echo "5) Instalar pacotes de desktop (usa sudo)"
  echo "6) Instalar ferramentas para agentes (usa sudo)"
  echo "7) Restaurar backup do ~/.bashrc"
  echo "8) Restaurar backup da configuração do tmux"
  echo "0) Sair"
}

# run_script SCRIPT [ARGS...]: uma falha não encerra o menu.
run_script() {
  local rc=0
  bash "$SCRIPT_DIR/scripts/$1" "${@:2}" "${DRY_ARGS[@]}" || rc=$?
  if ((rc != 0)); then
    echo "A operação terminou com código $rc." >&2
  fi
}

while true; do
  menu
  if ! read -r -p "Escolha: " choice; then
    echo
    echo "Entrada encerrada."
    exit 0
  fi
  case "$choice" in
    1) run_script setup-bash.sh ;;
    2) run_script setup-tmux.sh ;;
    3) run_script install-packages.sh base ;;
    4) run_script install-packages.sh development ;;
    5) run_script install-packages.sh desktop ;;
    6) run_script install-packages.sh agents ;;
    7) run_script restore.sh bash ;;
    8) run_script restore.sh tmux ;;
    0) exit 0 ;;
    *) echo "Opção inválida." >&2 ;;
  esac
done
