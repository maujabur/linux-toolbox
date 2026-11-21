#!/usr/bin/env bash
# Inclui configs/git/gitconfig na configuração pessoal do Git via include.path.
#
# Códigos de saída:
#   0  configurado agora, já estava configurado ou (--dry-run) seria configurado
#   1  erro (git ausente, arquivo inválido, falha ao gravar)
#   2  conflito: o arquivo de configuração é um link simbólico; nada foi alterado
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$SCRIPT_DIR/lib.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      echo "Uso: setup-git.sh [--dry-run]"
      echo "Adiciona ao TOPO de ~/.gitconfig um [include] para configs/git/gitconfig,"
      echo "de modo que as suas configurações existentes tenham prioridade."
      echo "Um backup com timestamp é criado antes. Não define nome, e-mail,"
      echo "credenciais nem assinatura. O include aponta para este clone."
      echo "Com --dry-run, apenas informa o que seria feito."
      exit 0
      ;;
    *) die "Opção desconhecida: $arg" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git não encontrado. Instale o pacote git (perfil base)."

SOURCE="$REPO_DIR/configs/git/gitconfig"
[[ -f "$SOURCE" ]] || die "Configuração não encontrada: $SOURCE"
git config --file "$SOURCE" --list >/dev/null || die "Configuração inválida: $SOURCE"

TARGET="$(git_global_config_path)"

if [[ -L "$TARGET" ]]; then
  banner err "CONFLITO: $TARGET é um link simbólico" \
    "(talvez gerenciado por outra ferramenta)." \
    "Nada foi alterado. Adicione manualmente ao arquivo real:" \
    "  git config --file \"\$(readlink -f '$TARGET')\" --add include.path '$SOURCE'"
  exit 2
fi

if [[ -f "$TARGET" ]] && git config --file "$TARGET" --get-all include.path 2>/dev/null | grep -Fxq -- "$SOURCE"; then
  banner ok "Já configurado: $TARGET inclui $SOURCE" \
    "Nada a fazer: o resultado desta opção já está em vigor."
  exit 0
fi

if ((DRY_RUN)); then
  if [[ -e "$TARGET" ]]; then
    log "[dry-run] Criaria um backup de $TARGET em $TARGET.bak.<timestamp>"
    log "[dry-run] Inseriria no topo de $TARGET: [include] path = $SOURCE"
  else
    log "[dry-run] Criaria $TARGET com: [include] path = $SOURCE"
  fi
  banner ok "[dry-run] Nenhuma alteração foi feita."
  exit 0
fi

# Monta o novo arquivo em um diretório privado criado por mktemp ao lado do
# original (mesmo sistema de arquivos) e só o troca (rename atômico) depois de
# validar e de guardar o backup; se algo falhar, o original fica intacto. O
# diretório é novo e exclusivo, então nenhum arquivo ou link preexistente é
# reutilizado, e o trap remove apenas o que este script criou.
mkdir -p -- "$(dirname "$TARGET")"
WORKDIR="$(mktemp -d -- "$TARGET.XXXXXX")" ||
  die "Não foi possível criar um diretório temporário ao lado de $TARGET."
trap 'rm -rf -- "$WORKDIR"' EXIT
TMP="$WORKDIR/novo"
if [[ -e "$TARGET" ]]; then
  cp -p -- "$TARGET" "$TMP"
  : >"$TMP"
fi
printf '# linux-toolbox: configuração pessoal (no topo para que o restante deste arquivo tenha prioridade)\n' >>"$TMP"
git config --file "$TMP" --add include.path "$SOURCE"
if [[ -e "$TARGET" ]]; then
  printf '\n' >>"$TMP"
  cat -- "$TARGET" >>"$TMP"
fi
git config --file "$TMP" --list >/dev/null || die "O arquivo resultante seria inválido (verifique $TARGET). Nada foi alterado."

if [[ -e "$TARGET" ]]; then
  backup="$(backup_copy "$TARGET")" || die "Falha ao criar o backup. Nada foi alterado."
  log "Backup criado: $backup"
fi
mv -fT -- "$TMP" "$TARGET"
banner ok "Git configurado: $TARGET agora inclui $SOURCE" "" \
  "Esta configuração não define nome nem e-mail. Se ainda não definiu:" \
  "  git config --global user.name  \"Seu Nome\"" \
  "  git config --global user.email \"seu-email\""
