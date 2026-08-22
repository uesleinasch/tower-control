#!/usr/bin/env bash
set -euo pipefail

say() { printf '\033[1m%s\033[0m\n' "$1"; }
die() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/control-tower.service"

[ -d /run/systemd/system ] || die "sem systemd nesta máquina — suba manualmente com: cd $RAIZ/app && bun run dev"

BUN="$(command -v bun)" || die "bun não encontrado no PATH"

mkdir -p "$UNIT_DIR"
cat >"$UNIT" <<EOF
[Unit]
Description=Control Tower — sala de decisões (porta 7878)
After=network-online.target

[Service]
ExecStart=$BUN run $RAIZ/app/src/server.ts
WorkingDirectory=$RAIZ/app
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now control-tower.service
say "serviço control-tower instalado e de pé"

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
