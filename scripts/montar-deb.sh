#!/usr/bin/env bash
# Uso: scripts/montar-deb.sh <versão> <pasta de artefatos> [pasta de saída]
# A pasta de artefatos traz: ai-memory, control-tower-servidor, control-tower-mcp, claude,
# cliente/ (bundle do flutter build linux) e control-tower.apk.
set -euo pipefail

die() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

VERSAO="${1:-}"
ARTEFATOS="${2:-}"
SAIDA="${3:-$PWD}"
[ -n "$VERSAO" ] && [ -d "$ARTEFATOS" ] || die "uso: $0 <versão> <pasta de artefatos> [saída]"
VERSAO="${VERSAO#v}"

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTEFATOS="$(cd "$ARTEFATOS" && pwd)"
for item in ai-memory control-tower-servidor control-tower-mcp claude cliente/control-tower control-tower.apk; do
  [ -e "$ARTEFATOS/$item" ] || die "falta o artefato $item em $ARTEFATOS"
done

PACOTE="control-tower_${VERSAO}_amd64"
PALCO="$(mktemp -d)/$PACOTE"
OPT="$PALCO/opt/control-tower"
trap 'rm -rf "$(dirname "$PALCO")"' EXIT

mkdir -p "$OPT/bin" "$PALCO/DEBIAN" "$PALCO/usr/lib/systemd/user" \
  "$PALCO/usr/share/applications" "$PALCO/usr/share/icons/hicolor/256x256/apps"

install -m 0755 "$ARTEFATOS/ai-memory" "$ARTEFATOS/control-tower-servidor" \
  "$ARTEFATOS/control-tower-mcp" "$ARTEFATOS/claude" "$OPT/bin/"
cp -r "$RAIZ/app/web" "$OPT/web"
cp -r "$RAIZ/app/modelos" "$OPT/modelos"
install -m 0644 "$RAIZ/scripts/memoria-config.toml" "$OPT/memoria-config.toml"
cp -r "$ARTEFATOS/cliente" "$OPT/cliente"
chmod 0755 "$OPT/cliente/control-tower"
install -m 0644 "$ARTEFATOS/control-tower.apk" "$OPT/cliente/control-tower.apk"

install -m 0644 "$RAIZ/packaging/deb/control-tower.service" "$RAIZ/packaging/deb/ai-memory.service" \
  "$PALCO/usr/lib/systemd/user/"
install -m 0644 "$RAIZ/packaging/deb/control-tower.desktop" "$PALCO/usr/share/applications/"
install -m 0644 "$RAIZ/cliente/assets/icone.png" "$PALCO/usr/share/icons/hicolor/256x256/apps/control-tower.png"

TAMANHO="$(du -sk --exclude=DEBIAN "$PALCO" | cut -f1)"
sed -e "s/@VERSAO@/$VERSAO/" -e "s/@TAMANHO@/$TAMANHO/" "$RAIZ/packaging/deb/control" >"$PALCO/DEBIAN/control"
install -m 0755 "$RAIZ/packaging/deb/postinst" "$RAIZ/packaging/deb/prerm" "$PALCO/DEBIAN/"

mkdir -p "$SAIDA"
dpkg-deb --build --root-owner-group -Zxz "$PALCO" "$SAIDA/$PACOTE.deb" >/dev/null
echo "$SAIDA/$PACOTE.deb"
