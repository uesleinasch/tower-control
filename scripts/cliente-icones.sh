#!/usr/bin/env bash
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$RAIZ/app/web/icone.svg"
RES="$RAIZ/cliente/android/app/src/main/res"
ASSETS="$RAIZ/cliente/assets"
command -v convert >/dev/null || { echo "precisa do ImageMagick (convert)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
grep -v '<rect width="512" height="512"' "$SVG" >"$TMP/frente.svg"

rasterizar() { convert -background none -density 384 "$1" -resize "$2x$2" "$3"; }

for par in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  densidade=${par%%:*}
  lado=${par#*:}
  mkdir -p "$RES/mipmap-$densidade"
  rasterizar "$SVG" "$lado" "$RES/mipmap-$densidade/ic_launcher.png"
  rasterizar "$TMP/frente.svg" $((lado * 9 / 4)) "$RES/mipmap-$densidade/ic_launcher_foreground.png"
done

mkdir -p "$RES/mipmap-anydpi-v26" "$RES/values"
cat >"$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF
cat >"$RES/values/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#10131A</color>
</resources>
EOF

rasterizar "$SVG" 256 "$ASSETS/icone.png"
echo "ícones gerados a partir de $SVG"
