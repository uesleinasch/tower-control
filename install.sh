#!/usr/bin/env bash
set -euo pipefail

# Instala o control-tower nesta máquina e registra o serviço para subir no boot.
#
# De dentro de um clone:            ./install.sh
# Em máquina nova (clona antes):    ./install.sh git@github.com:<usuario>/control-tower.git
# Destino do clone (opcional):      CONTROL_TOWER_DIR=~/apps/control-tower ./install.sh <url>

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

command -v claude >/dev/null 2>&1 ||
  die "Claude Code não encontrado — o motor das conversas depende dele (https://claude.com/claude-code)"

if ! command -v bun >/dev/null 2>&1; then
  say "instalando bun"
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"
  command -v bun >/dev/null 2>&1 || die "bun instalou mas não entrou no PATH — abra um terminal novo e rode de novo"
fi

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$AQUI/scripts/servico.sh" ]; then
  RAIZ="$AQUI"
else
  URL="${1:-}"
  [ -n "$URL" ] || die "fora de um clone, passe a URL do repositório: ./install.sh <url-do-git>"
  RAIZ="${CONTROL_TOWER_DIR:-$HOME/control-tower}"
  say "clonando em $RAIZ"
  git clone "$URL" "$RAIZ"
fi

say "instalando dependências"
(cd "$RAIZ/app" && bun install)

say "registrando o serviço (boot + restart automático)"
bash "$RAIZ/scripts/servico.sh"

say "pronto — endereços (local, rede e tailscale) no log do serviço:"
echo "  journalctl --user -u control-tower.service -n 5 --no-pager"
echo
echo "MCP das decisões para outras sessões Claude Code (opcional):"
echo "  claude mcp add --scope user control-tower -- bun run $RAIZ/app/mcp/server.ts"
