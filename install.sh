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

command -v cargo >/dev/null 2>&1 ||
  die "cargo não encontrado — o ai-memory (memória das personas) é Rust: https://rustup.rs. Ou instale pelo .deb do GitHub Release."
say "compilando o ai-memory (demora na primeira vez)"
(cd "$RAIZ/ai-memory" && cargo build --release --locked -p ai-memory-cli)

say "registrando o serviço (boot + restart automático)"
bash "$RAIZ/scripts/servico.sh"

if command -v flutter >/dev/null 2>&1 || [ -x "$HOME/flutter/bin/flutter" ] || [ -x "$HOME/development/flutter/bin/flutter" ]; then
  say "instalando o app de desktop e o APK do celular"
  bash "$RAIZ/scripts/instalar-cliente.sh" || echo "o app não instalou — rode de novo depois: bash scripts/instalar-cliente.sh"
else
  echo "sem Flutter nesta máquina: o app de desktop fica para depois (bash scripts/instalar-cliente.sh)"
fi

say "pronto — endereços (local, rede e tailscale) no log do serviço:"
echo "  journalctl --user -u control-tower.service -n 5 --no-pager"
echo
echo "MCP das decisões para outras sessões Claude Code (opcional):"
echo "  claude mcp add --scope user control-tower -- bun run $RAIZ/app/mcp/server.ts"
