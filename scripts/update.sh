#!/usr/bin/env bash
# Atualiza este clone a partir do remoto configurado (normalmente o GitHub),
# somente por avanço rápido (fast-forward): nunca reescreve nem descarta nada.
#
# Códigos de saída:
#   0  atualizado agora, já estava atualizado ou (--dry-run) apenas verificado
#   1  erro (git ausente, sem rede, clone sem upstream, cancelado)
#   2  conflito: alterações locais ou histórico divergente; nada foi alterado
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$SCRIPT_DIR/lib.sh"

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    -h | --help)
      echo "Uso: update.sh [--dry-run] [--yes]"
      echo "Atualiza este clone a partir do remoto (git fetch + merge --ff-only)."
      echo "Mostra os commits e as alterações antes e pede confirmação [s/N]."
      echo "Recusa atualizar se houver alterações locais ou histórico divergente."
      echo "Com --dry-run, apenas consulta o remoto (git ls-remote), sem gravar nada."
      exit 0
      ;;
    *) die "Opção desconhecida: $arg" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git não encontrado. Instale o pacote git (perfil base)."

# git -C "$REPO_DIR" ...; --no-optional-locks evita que um simples "status" grave no .git.
g() { git --no-optional-locks -C "$REPO_DIR" "$@"; }

[[ "$(g rev-parse --show-toplevel 2>/dev/null || true)" == "$(cd -- "$REPO_DIR" && pwd -P)" ]] ||
  die "$REPO_DIR não é a raiz de um clone git; a atualização não está disponível."

BRANCH="$(g symbolic-ref --short -q HEAD || true)"
[[ -n "$BRANCH" ]] || die "O clone está em HEAD destacado; faça checkout de uma branch antes."
REMOTE="$(g config --get "branch.$BRANCH.remote" || true)"
MERGE_REF="$(g config --get "branch.$BRANCH.merge" || true)"
[[ -n "$REMOTE" && -n "$MERGE_REF" ]] || die "A branch $BRANCH não tem upstream configurado."
URL="$(g remote get-url "$REMOTE")" || die "Remoto não encontrado: $REMOTE"

if [[ -n "$(g status --porcelain)" ]]; then
  banner err "CONFLITO: há alterações locais não commitadas em $REPO_DIR." \
    "Nada foi alterado. Faça commit ou guarde as alterações (git stash)" \
    "e execute a atualização novamente."
  exit 2
fi

LOCAL="$(g rev-parse HEAD)"
log "Clone:   $REPO_DIR"
log "Remoto:  $REMOTE ($URL)"
log "Branch:  $BRANCH"
log "Versão:  ${LOCAL:0:12}"

if ((DRY_RUN)); then
  REMOTE_HASH="$(g ls-remote "$REMOTE" "$MERGE_REF" | awk 'NR==1 {print $1}')" ||
    die "Não foi possível consultar o remoto."
  [[ -n "$REMOTE_HASH" ]] || die "O remoto não tem a referência $MERGE_REF."
  if [[ "$REMOTE_HASH" == "$LOCAL" ]]; then
    log "[dry-run] O remoto está na mesma versão (${REMOTE_HASH:0:12})."
  else
    log "[dry-run] O remoto está em ${REMOTE_HASH:0:12}, diferente da sua versão."
    log "[dry-run] A atualização real faria git fetch e git merge --ff-only."
  fi
  banner ok "[dry-run] Nenhuma alteração foi feita."
  exit 0
fi

g fetch --quiet "$REMOTE" "$MERGE_REF" || die "Falha ao buscar atualizações em $URL."
TARGET="$(g rev-parse FETCH_HEAD)"

if [[ "$TARGET" == "$LOCAL" ]]; then
  banner ok "Já atualizado: ${LOCAL:0:12}" \
    "Nada a fazer: o clone já está na versão mais recente."
  exit 0
elif g merge-base --is-ancestor "$TARGET" "$LOCAL"; then
  banner ok "Nada a atualizar: seus commits locais estão à frente do remoto." \
    "Nada a fazer: não há versão nova a aplicar."
  exit 0
elif ! g merge-base --is-ancestor "$LOCAL" "$TARGET"; then
  banner err "CONFLITO: o histórico local e o do remoto divergiram." \
    "Nada foi alterado. Resolva manualmente (git pull --rebase ou merge)."
  exit 2
fi

log
log "Commits novos:"
g log --oneline "$LOCAL..$TARGET"
log
log "Arquivos alterados:"
g diff --stat "$LOCAL..$TARGET"
log
warn "Leia as alterações antes de executar os scripts atualizados."
confirm "Aplicar essa atualização (git merge --ff-only)?" || {
  banner warn "CANCELADO. Nada foi alterado."
  exit 1
}

g merge --ff-only --quiet "$TARGET" || die "Falha ao aplicar a atualização. Nada foi alterado."
banner ok "Atualizado: ${LOCAL:0:12} -> ${TARGET:0:12}" "" \
  "PRÓXIMO PASSO: execute o bootstrap novamente para usar a" \
  "versão nova. Para voltar à anterior (descarta alterações locais):" \
  "  git -C $REPO_DIR reset --hard ${LOCAL:0:12}"
