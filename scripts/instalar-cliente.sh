#!/usr/bin/env bash
set -euo pipefail

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
avisa() { printf '\033[33m%s\033[0m\n' "$1"; }
die() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENTE="$RAIZ/cliente"
DESTINO="$HOME/.local/share/control-tower-cliente"
ICONE="$HOME/.local/share/icons/hicolor/256x256/apps/control-tower.png"
MENU="$HOME/.local/share/applications/control-tower.desktop"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/control-tower.desktop"

FLUTTER="${FLUTTER:-}"
if [ -z "$FLUTTER" ]; then
  for candidato in "$(command -v flutter || true)" "$HOME/flutter/bin/flutter" "$HOME/development/flutter/bin/flutter"; do
    if [ -n "$candidato" ] && [ -x "$candidato" ]; then FLUTTER="$candidato"; break; fi
  done
fi
[ -n "$FLUTTER" ] || die "flutter não encontrado — instale o SDK ou aponte FLUTTER=/caminho/bin/flutter"

faltando=()
for modulo in gtk+-3.0 x11 xi; do
  pkg-config --exists "$modulo" 2>/dev/null || faltando+=("$modulo")
done
[ ${#faltando[@]} -eq 0 ] ||
  die "faltam bibliotecas de build do Linux (${faltando[*]}): sudo apt install -y libgtk-3-dev libx11-dev libxi-dev"

cd "$CLIENTE"
say "baixando dependências do app"
"$FLUTTER" pub get

say "compilando o app de desktop"
"$FLUTTER" build linux --release

APK=""
say "compilando o APK do celular"
if "$FLUTTER" build apk --release; then
  APK="$CLIENTE/build/app/outputs/flutter-apk/app-release.apk"
else
  avisa "o APK não compilou — o desktop segue instalado, mas 'Instalar e conectar' fica indisponível"
fi

say "instalando em $DESTINO"
pkill -x control-tower 2>/dev/null || true
rm -rf "$DESTINO"
mkdir -p "$DESTINO"
cp -r "$CLIENTE/build/linux/x64/release/bundle/." "$DESTINO/"
[ -n "$APK" ] && cp "$APK" "$DESTINO/control-tower.apk"

mkdir -p "$(dirname "$ICONE")" "$(dirname "$MENU")" "$(dirname "$AUTOSTART")"
cp "$CLIENTE/assets/icone.png" "$ICONE"

entrada() {
  cat <<EOF
[Desktop Entry]
Type=Application
Name=Control Tower
Comment=Sala de decisões
Exec="$DESTINO/control-tower"$1
Icon=control-tower
Terminal=false
Categories=Utility;
StartupWMClass=dev.ueslei.controltower
EOF
}

entrada "" >"$MENU"
if [ "${SEM_AUTOSTART:-}" != "1" ]; then
  { entrada " --bandeja"; echo "X-GNOME-Autostart-enabled=true"; } >"$AUTOSTART"
  say "o app sobe na bandeja a cada login (desligue em Configuração → Inicialização)"
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$(dirname "$MENU")" || true

setsid "$DESTINO/control-tower" --bandeja >/dev/null 2>&1 < /dev/null &
say "pronto — Control Tower está na bandeja e no menu de aplicativos"
