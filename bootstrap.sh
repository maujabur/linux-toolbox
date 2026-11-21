#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/scripts/lib.sh"

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
  echo "7) Configurar Git (aliases e padrões seguros; não define identidade)"
  echo "8) Restaurar backups..."
  echo "9) Atualizar este clone a partir do GitHub"
  echo "0) Sair"
}

restore_menu() {
  echo
  echo "Restaurar backup de:"
  echo "1) ~/.bashrc"
  echo "2) Configuração do tmux"
  echo "3) Configuração do Git"
  echo "0) Voltar"
}

# Pausa para que o resultado não seja coberto pelo menu seguinte.
# Enter volta ao menu; q (ou 0) encerra o script.
pause() {
  local answer=""
  printf 'Enter = voltar ao menu, q = sair: ' >&2
  read -r answer || true
  case "$answer" in
    q | Q | 0)
      echo "Até logo." >&2
      exit 0
      ;;
  esac
}

# report_rc CODIGO: destaca uma falha de operação (o menu continua).
report_rc() {
  if (($1 != 0)); then
    banner err "A operação terminou com código $1." "Veja as mensagens acima."
  fi
}

# run_script SCRIPT [ARGS...]: uma falha não encerra o menu.
run_script() {
  local rc=0
  bash "$SCRIPT_DIR/scripts/$1" "${@:2}" "${DRY_ARGS[@]}" || rc=$?
  report_rc "$rc"
  pause
}

# Executa restore.sh para o alvo escolhido no submenu; 0 volta sem pausa.
run_restore_menu() {
  local choice=""
  restore_menu
  read -r -p "Escolha: " choice || return 0
  case "$choice" in
    1) run_script restore.sh bash ;;
    2) run_script restore.sh tmux ;;
    3) run_script restore.sh git ;;
    0) ;;
    *)
      banner err "Opção inválida: $choice"
      pause
      ;;
  esac
}

# A atualização pode trocar os próprios arquivos do menu: se a versão mudou,
# encerra (sem pausa) e pede para executar o bootstrap de novo.
run_update() {
  local before after rc=0
  before="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)"
  bash "$SCRIPT_DIR/scripts/update.sh" "${DRY_ARGS[@]}" || rc=$?
  after="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "$before" && "$before" != "$after" ]]; then
    banner ok "O clone foi atualizado." \
      "Execute o bootstrap novamente para carregar a nova versão."
    exit 0
  fi
  report_rc "$rc"
  pause
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
    7) run_script setup-git.sh ;;
    8) run_restore_menu ;;
    9) run_update ;;
    0) exit 0 ;;
    *)
      banner err "Opção inválida: $choice"
      pause
      ;;
  esac
done
