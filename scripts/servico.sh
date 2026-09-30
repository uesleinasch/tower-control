#!/usr/bin/env bash
set -euo pipefail

say() { printf '\033[1m%s\033[0m\n' "$1"; }
die() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/control-tower.service"
UNIT_MEMORIA="$UNIT_DIR/ai-memory.service"
MEMORIA_BIN="$RAIZ/ai-memory/target/release/ai-memory"
MEMORIA_DADOS="$HOME/.local/share/control-tower/memoria"

[ -d /run/systemd/system ] || die "sem systemd nesta máquina — suba manualmente com: cd $RAIZ/app && bun run dev"

BUN="$(command -v bun)" || die "bun não encontrado no PATH"
[ -x "$MEMORIA_BIN" ] || die "ai-memory não compilado — rode: cd $RAIZ/ai-memory && cargo build --release -p ai-memory-cli"

mkdir -p "$UNIT_DIR" "$MEMORIA_DADOS"
cat >"$UNIT_MEMORIA" <<EOF
[Unit]
Description=ai-memory — memória das personas do Control Tower (127.0.0.1:49374)

[Service]
ExecStart=$MEMORIA_BIN --data-dir $MEMORIA_DADOS --config $RAIZ/scripts/memoria-config.toml serve --transport http
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

cat >"$UNIT" <<EOF
[Unit]
Description=Control Tower — sala de decisões (porta 7878)
After=network-online.target ai-memory.service
Wants=ai-memory.service

[Service]
ExecStart=$BUN run $RAIZ/app/src/server.ts
WorkingDirectory=$RAIZ/app
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now ai-memory.service
systemctl --user enable --now control-tower.service
say "serviços ai-memory e control-tower instalados e de pé"

# Sem linger o serviço de usuário só sobe no login; com ele, sobe no boot.
if loginctl show-user "$USER" 2>/dev/null | grep -q '^Linger=yes'; then
  say "linger já ativo — o serviço sobe no boot, mesmo sem login"
elif loginctl enable-linger "$USER" 2>/dev/null; then
  say "linger ativado — o serviço sobe no boot, mesmo sem login"
else
  say "atenção: não consegui ativar o linger (rode: sudo loginctl enable-linger $USER)"
  say "sem linger, o serviço sobe apenas quando você faz login"
fi

systemctl --user --no-pager status control-tower.service | head -5
