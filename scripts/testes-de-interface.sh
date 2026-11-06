#!/usr/bin/env bash
# uso: bash scripts/testes-de-interface.sh [web|desktop|celular|conjuntas] [cena]
set -u

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$RAIZ/app"
WEB="$APP/interface/web"
CLIENTE="$RAIZ/cliente"
FLUTTER="${FLUTTER:-$HOME/flutter/bin/flutter}"
AAPT="${AAPT:-$(ls -d "$HOME"/Android/Sdk/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)}"
AAPT="${AAPT:-aapt}"
PACOTE_DE_TESTE=dev.ueslei.controltower.teste
APK="$CLIENTE/build/app/outputs/flutter-apk/app-debug.apk"

ALVO="${1:-tudo}"
CENA="${2:-}"
case "$ALVO" in
  tudo | web | desktop | celular | conjuntas) ;;
  *)
    echo "uso: bash scripts/testes-de-interface.sh [web|desktop|celular|conjuntas] [cena]" >&2
    exit 2
    ;;
esac

PASTA=$(mktemp -d "/tmp/ct-interface-$(date +%Y%m%d-%H%M%S)-XXXX") || exit 1
RESULTADO="$PASTA/resultado.tsv"
printf 'etapa\tplataforma\tresultado\tsegundos\tmotivo\n' > "$RESULTADO"

SERIAL=""
MOTIVO=""
INSTALOU=0
REVERSOS=()
XDGS=()
FALHAS=0

grupo_vivo() { kill -0 -- "-$1" 2> /dev/null; }

encerrar_grupo() {
  local pid=$1 servidor=${2:-}
  [ -n "$pid" ] || return 0
  if grupo_vivo "$pid"; then
    kill -TERM -- "-$pid" 2> /dev/null
    for _ in $(seq 250); do
      grupo_vivo "$pid" || break
      sleep 0.1
    done
    grupo_vivo "$pid" && kill -KILL -- "-$pid" 2> /dev/null
  fi
  if [ -n "$servidor" ] && [ "$servidor" != null ] && grupo_vivo "$servidor"; then
    kill -KILL -- "-$servidor" 2> /dev/null
  fi
}

encerrar_ambientes() {
  local arquivo pasta servidor
  while IFS= read -r arquivo; do
    if [ "$(basename "$arquivo")" = subir.pid ]; then pasta=$(dirname "$arquivo"); else pasta=${arquivo%.subir.pid}; fi
    servidor=""
    [ -f "$pasta/ambiente.json" ] && servidor=$(jq -r .pidDoServidor "$pasta/ambiente.json" 2> /dev/null)
    encerrar_grupo "$(cat "$arquivo")" "$servidor"
    rm -f "$arquivo"
    rm -rf "$pasta"
  done < <(find "$PASTA" -name '*subir.pid' 2> /dev/null)
}

limpar_xdg() {
  local x=$1
  mountpoint -q "$x/run/doc" 2> /dev/null && fusermount -u "$x/run/doc" 2> /dev/null
  rm -rf "$x" 2> /dev/null || { sleep 1; rm -rf "$x"; }
}

limpar() {
  local estado=$?
  trap '' INT TERM HUP
  trap - EXIT
  echo "limpando, aguarde…" >&2
  [ "$estado" -ge 129 ] && printf 'rodada\t-\tinterrompida\t%s\tsinal %s\n' "$SECONDS" "$((estado - 128))" >> "$RESULTADO"
  local f
  for f in "$PASTA"/*.lado.pid; do
    [ -f "$f" ] || continue
    encerrar_grupo "$(cat "$f")"
    rm -f "$f"
  done
  encerrar_ambientes
  for f in "${REVERSOS[@]}"; do adb -s "$SERIAL" reverse --remove "tcp:$f" > /dev/null 2>&1; done
  [ "$INSTALOU" = 1 ] && adb -s "$SERIAL" uninstall "$PACOTE_DE_TESTE" > /dev/null 2>&1
  for f in "${XDGS[@]}"; do limpar_xdg "$f"; done
  exit "$estado"
}
trap limpar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

titulo() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

registrar() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" >> "$RESULTADO"
  [ "$3" = falhou ] && FALHAS=$((FALHAS + 1))
  printf '%s/%s: %s (%s s)%s\n' "$1" "$2" "$3" "$4" "${5:+. $5}"
}

faltando() {
  local falta=() c
  for c in "$@"; do command -v "$c" > /dev/null 2>&1 || falta+=("$c"); done
  echo "${falta[*]}"
}

lancar() {
  local nome=$1 dir=$2
  shift 2
  (
    cd "$dir" || exit 1
    inicio=$SECONDS
    setsid "$@" > "$PASTA/$nome.log" 2>&1 < /dev/null &
    filho=$!
    echo "$filho" > "$PASTA/$nome.lado.pid"
    wait "$filho"
    rc=$?
    echo "$rc $((SECONDS - inicio))" > "$PASTA/$nome.fim"
    rm -f "$PASTA/$nome.lado.pid"
    exit "$rc"
  ) &
  echo $! > "$PASTA/$nome.espera"
}

esperar() {
  local nome
  for nome in "$@"; do wait "$(cat "$PASTA/$nome.espera")" 2> /dev/null; done
}

terminou() {
  local nome=$1
  [ -f "$PASTA/$nome.fim" ] || { echo "1 0"; return; }
  cat "$PASTA/$nome.fim"
}

subir_ambiente() {
  local nome=$1 pasta="$PASTA/$1"
  mkdir -p "$pasta"
  (cd "$APP" && exec setsid bun run interface/subir.ts "$pasta") > "$PASTA/$nome.subir.log" 2>&1 < /dev/null &
  local pid=$!
  echo "$pid" > "$pasta.subir.pid"
  for _ in $(seq 600); do
    [ -s "$pasta/ambiente.json" ] && return 0
    kill -0 "$pid" 2> /dev/null || break
    sleep 0.1
  done
  MOTIVO="o ambiente $nome não subiu, veja $PASTA/$nome.subir.log"
  return 1
}

guardar_ambiente() {
  local nome=$1 json="$PASTA/$1/ambiente.json"
  [ -f "$json" ] || return 0
  cp "$(jq -r .logServidor "$json")" "$PASTA/$nome.servidor.log" 2> /dev/null
  curl -s -m 5 "$(jq -r .modelo "$json")/_controle/sem-regra" > "$PASTA/$nome.sem-regra.json" 2> /dev/null
}

descer_ambiente() {
  local nome=$1 pasta="$PASTA/$1"
  [ -f "$pasta.subir.pid" ] || return 0
  local servidor=""
  [ -f "$pasta/ambiente.json" ] && servidor=$(jq -r .pidDoServidor "$pasta/ambiente.json")
  encerrar_grupo "$(cat "$pasta.subir.pid")" "$servidor"
  rm -f "$pasta.subir.pid"
  rm -rf "$pasta"
}

mostrar_falha() {
  local plataforma=$1 log=$2
  shift 2
  echo "-- $plataforma falhou. Cenas vermelhas:"
  grep -E '✘|\[E\]$' "$log" 2> /dev/null | sed -E 's/^[[:space:]]*/   /' | sort -u
  echo "   log da plataforma: $log"
  local caminho
  for caminho in "$@"; do
    [ -e "$caminho" ] && echo "   $caminho"
  done
  for caminho in "$PASTA"/*.sem-regra.json "$PASTA"/web/*.sem-regra.json; do
    [ -s "$caminho" ] || continue
    [ "$(head -c 2 "$caminho")" = "[]" ] && continue
    echo "   sem-regra ($caminho): $(head -c 1500 "$caminho")"
  done
}

aparelho_pronto() {
  MOTIVO=""
  SERIAL=${CT_SERIAL:-$(adb devices 2> /dev/null | awk 'NR > 1 && $2 == "device" { print $1; exit }')}
  [ -n "$SERIAL" ] || { MOTIVO="nenhum aparelho no adb devices"; return 1; }
  local janela energia
  janela=$(adb -s "$SERIAL" shell dumpsys window 2> /dev/null)
  if grep -Eq 'mDreamingLockscreen=true|isKeyguardShowing=true' <<< "$janela"; then
    MOTIVO="aparelho $SERIAL com a tela bloqueada"
    return 1
  fi
  grep -q 'mDreamingLockscreen=false' <<< "$janela" || { MOTIVO="não deu para conferir o bloqueio do aparelho $SERIAL"; return 1; }
  energia=$(adb -s "$SERIAL" shell dumpsys power 2> /dev/null)
  grep -q 'mWakefulness=Awake' <<< "$energia" || { MOTIVO="aparelho $SERIAL com a tela apagada"; return 1; }
  return 0
}

instalar_pacote_de_teste() {
  [ "$INSTALOU" = 1 ] && return 0
  (cd "$CLIENTE" && CT_APP_TESTE=1 "$FLUTTER" build apk --debug) > "$PASTA/celular-apk.log" 2>&1 || {
    MOTIVO="o build do APK de teste falhou, veja $PASTA/celular-apk.log"
    return 1
  }
  local pacote
  pacote=$("$AAPT" dump badging "$APK" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
  if [ "$pacote" != "$PACOTE_DE_TESTE" ]; then
    MOTIVO="o APK saiu com o pacote '$pacote', e não $PACOTE_DE_TESTE: nada foi instalado"
    return 1
  fi
  adb -s "$SERIAL" install -r "$APK" >> "$PASTA/celular-apk.log" 2>&1 || {
    MOTIVO="o adb install falhou, veja $PASTA/celular-apk.log"
    return 1
  }
  INSTALOU=1
  adb -s "$SERIAL" shell pm grant "$PACOTE_DE_TESTE" android.permission.POST_NOTIFICATIONS >> "$PASTA/celular-apk.log" 2>&1
  return 0
}

reverso() {
  local porta=$1
  if adb -s "$SERIAL" reverse --list | grep -q "tcp:$porta "; then
    MOTIVO="a porta $porta já estava no adb reverse do aparelho: não mexo nela"
    return 1
  fi
  adb -s "$SERIAL" reverse "tcp:$porta" "tcp:$porta" > /dev/null || { MOTIVO="o adb reverse da porta $porta falhou"; return 1; }
  REVERSOS+=("$porta")
}

marca_do_app_real() {
  adb -s "$SERIAL" shell dumpsys package dev.ueslei.controltower 2> /dev/null | sed -n 's/^ *lastUpdateTime=//p' | head -1
}

conferir_app_real() {
  local antes=$1 depois
  depois=$(marca_do_app_real)
  [ "$antes" = "$depois" ] && return 0
  printf '\033[31m!!! o app dev.ueslei.controltower mudou no aparelho (lastUpdateTime %s -> %s)\033[0m\n' "${antes:-ausente}" "${depois:-ausente}" >&2
  MOTIVO="o app real dev.ueslei.controltower mudou no aparelho (lastUpdateTime ${antes:-ausente} -> ${depois:-ausente})"
  return 1
}

tirar_reverso() {
  local porta=$1 resto=() p achou=0
  for p in "${REVERSOS[@]}"; do
    if [ "$p" = "$porta" ]; then achou=1; else resto+=("$p"); fi
  done
  [ "$achou" = 1 ] || return 0
  adb -s "$SERIAL" reverse --remove "tcp:$porta" > /dev/null 2>&1
  REVERSOS=("${resto[@]}")
}

portas_do_ambiente() {
  local json="$PASTA/$1/ambiente.json"
  echo "$(jq -r .porta "$json") $(jq -r .modelo "$json" | sed 's/.*://')"
}

comando_do_desktop() {
  local x
  x=$(mktemp -d /tmp/ct-xdg-XXXXXX) || { MOTIVO="não deu para criar a pasta XDG em /tmp"; return 1; }
  XDGS+=("$x")
  mkdir -p "$x/data" "$x/config" "$x/cache" "$x/run"
  chmod 700 "$x/run"
  DESKTOP=(env TMPDIR="$x" xvfb-run -a env -u WAYLAND_DISPLAY TMPDIR="${TMPDIR:-/tmp}" XDG_DATA_HOME="$x/data" XDG_CONFIG_HOME="$x/config" XDG_CACHE_HOME="$x/cache"
    XDG_RUNTIME_DIR="$x/run" dbus-run-session -- "$FLUTTER" test integration_test/desktop_test.dart -d linux)
}

comando_do_celular() {
  CELULAR=(env CT_APP_TESTE=1 "$FLUTTER" test integration_test/celular_test.dart -d "$SERIAL" --no-uninstall)
}

etapa_web() {
  titulo "web"
  local falta
  falta=$(faltando bun npx jq)
  [ -x "$WEB/node_modules/.bin/playwright" ] || falta="$falta node_modules (cd app/interface/web && npm ci && npx playwright install chromium)"
  if [ -n "${falta// /}" ]; then
    registrar web web falhou 0 "falta: $falta"
    return
  fi
  mkdir -p "$PASTA/web"
  local filtro=()
  [ -n "$CENA" ] && filtro=(-g "$CENA")
  lancar web "$WEB" env CT_PASTA_DA_RODADA="$PASTA/web" npx playwright test "${filtro[@]}" --output "$PASTA/web-resultados"
  esperar web
  read -r rc segundos < <(terminou web)
  if [ "$rc" = 0 ]; then
    registrar web web passou "$segundos"
  else
    registrar web web falhou "$segundos" "veja $PASTA/web.log"
    mostrar_falha web "$PASTA/web.log" "$PASTA/web-resultados" "$PASTA"/web/*.servidor.log
  fi
}

etapa_desktop() {
  titulo "desktop"
  local falta
  falta=$(faltando bun jq curl xvfb-run xdotool xmodmap dbus-run-session "$FLUTTER")
  if [ -n "$falta" ]; then
    registrar desktop desktop falhou 0 "falta: $falta"
    return
  fi
  if ! subir_ambiente desktop; then
    registrar desktop desktop falhou 0 "$MOTIVO"
    descer_ambiente desktop
    return
  fi
  if ! comando_do_desktop; then
    registrar desktop desktop falhou 0 "$MOTIVO"
    descer_ambiente desktop
    return
  fi
  local filtro=()
  [ -n "$CENA" ] && filtro=(--plain-name "$CENA")
  lancar desktop "$CLIENTE" "${DESKTOP[@]}" --dart-define=CT_AMBIENTE="$PASTA/desktop/ambiente.json" "${filtro[@]}"
  esperar desktop
  read -r rc segundos < <(terminou desktop)
  limpar_xdg "${XDGS[-1]}"
  if [ "$rc" = 0 ]; then
    registrar desktop desktop passou "$segundos"
  else
    guardar_ambiente desktop
    registrar desktop desktop falhou "$segundos" "veja $PASTA/desktop.log"
    mostrar_falha desktop "$PASTA/desktop.log" "$PASTA/capturas" "$PASTA/desktop.servidor.log"
  fi
  descer_ambiente desktop
}

etapa_celular() {
  titulo "celular"
  local falta
  falta=$(faltando adb bun jq curl "$FLUTTER" "$AAPT")
  if [ -n "$falta" ]; then
    registrar celular celular falhou 0 "falta: $falta"
    return
  fi
  if ! aparelho_pronto; then
    registrar celular celular pulou 0 "$MOTIVO"
    return
  fi
  local marca
  marca=$(marca_do_app_real)
  if ! subir_ambiente celular; then
    registrar celular celular falhou 0 "$MOTIVO"
    descer_ambiente celular
    return
  fi
  if ! instalar_pacote_de_teste; then
    registrar celular celular falhou 0 "$MOTIVO"
    descer_ambiente celular
    return
  fi
  local portas p
  portas=$(portas_do_ambiente celular)
  for p in $portas; do
    if ! reverso "$p"; then
      registrar celular celular falhou 0 "$MOTIVO"
      descer_ambiente celular
      return
    fi
  done
  comando_do_celular
  local filtro=()
  [ -n "$CENA" ] && filtro=(--plain-name "$CENA")
  lancar celular "$CLIENTE" "${CELULAR[@]}" --dart-define=CT_AMBIENTE_JSON="$(base64 -w0 "$PASTA/celular/ambiente.json")" "${filtro[@]}"
  esperar celular
  read -r rc segundos < <(terminou celular)
  local motivo=""
  if [ "$rc" = 0 ] && [ -z "$CENA" ]; then
    local arquivo
    for arquivo in cena2 cena2-aviso cena2-auto; do
      grep -qx "$arquivo" "$PASTA/celular/$arquivo.txt" 2> /dev/null || motivo="$motivo faltou $arquivo.txt;"
    done
    [ -e "$PASTA/celular/cena2-negado.txt" ] && motivo="$motivo o comando negado rodou;"
    [ -n "$motivo" ] && rc=1
  fi
  conferir_app_real "$marca" || { rc=1; motivo="$MOTIVO"; }
  for p in $portas; do tirar_reverso "$p"; done
  if [ "$rc" = 0 ]; then
    registrar celular celular passou "$segundos"
  else
    guardar_ambiente celular
    registrar celular celular falhou "$segundos" "${motivo:-veja $PASTA/celular.log}"
    mostrar_falha celular "$PASTA/celular.log" "$PASTA/capturas" "$PASTA/celular.servidor.log"
  fi
  descer_ambiente celular
}

etapa_conjuntas() {
  titulo "conjuntas"
  local falta lados="web,desktop" com_celular=0
  falta=$(faltando bun npx jq curl xvfb-run xdotool xmodmap dbus-run-session "$FLUTTER")
  [ -x "$WEB/node_modules/.bin/playwright" ] || falta="$falta node_modules"
  local marca=""
  if [ -n "${falta// /}" ]; then
    registrar conjuntas web falhou 0 "falta: $falta"
    registrar conjuntas desktop falhou 0 "falta: $falta"
    return
  fi
  local falta_do_celular
  falta_do_celular=$(faltando adb "$AAPT")
  if [ -n "$falta_do_celular" ]; then
    registrar conjuntas celular falhou 0 "falta: $falta_do_celular"
  elif aparelho_pronto; then
    lados="$lados,celular"
    com_celular=1
  else
    registrar conjuntas celular pulou 0 "$MOTIVO"
  fi
  if ! subir_ambiente conjuntas; then
    registrar conjuntas web falhou 0 "$MOTIVO"
    registrar conjuntas desktop falhou 0 "$MOTIVO"
    descer_ambiente conjuntas
    return
  fi
  local portas="" p
  if [ "$com_celular" = 1 ]; then
    marca=$(marca_do_app_real)
    if instalar_pacote_de_teste; then
      portas=$(portas_do_ambiente conjuntas)
      for p in $portas; do reverso "$p" || break; done
      [ "${#REVERSOS[@]}" -ge 2 ]
    else
      false
    fi
    if [ $? != 0 ]; then
      registrar conjuntas celular falhou 0 "$MOTIVO"
      com_celular=0
      lados="web,desktop"
    fi
  fi
  local json="$PASTA/conjuntas/ambiente.json" filtro="conjunta: $CENA"
  if ! comando_do_desktop; then
    registrar conjuntas web falhou 0 "$MOTIVO"
    registrar conjuntas desktop falhou 0 "$MOTIVO"
    descer_ambiente conjuntas
    return
  fi
  lancar conjuntas-web "$WEB" env CT_AMBIENTE_DE_PE="$json" CT_LADOS="$lados" CT_PASTA_DA_RODADA="$PASTA" \
    npx playwright test cenas/painel.spec.ts -g "$filtro" --output "$PASTA/conjuntas-web-resultados"
  lancar conjuntas-desktop "$CLIENTE" "${DESKTOP[@]}" --dart-define=CT_AMBIENTE="$json" --dart-define=CT_LADOS="$lados" --plain-name "$filtro"
  local nomes=(conjuntas-web conjuntas-desktop)
  if [ "$com_celular" = 1 ]; then
    comando_do_celular
    lancar conjuntas-celular "$CLIENTE" "${CELULAR[@]}" --dart-define=CT_AMBIENTE_JSON="$(base64 -w0 "$json")" \
      --dart-define=CT_LADOS="$lados" --plain-name "$filtro"
    nomes+=(conjuntas-celular)
  fi
  esperar "${nomes[@]}"
  limpar_xdg "${XDGS[-1]}"
  for p in $portas; do tirar_reverso "$p"; done
  local nome rc segundos falhou=0
  if [ "$com_celular" = 1 ] && ! conferir_app_real "$marca"; then
    registrar conjuntas app-real falhou 0 "$MOTIVO"
    falhou=1
  fi
  for nome in "${nomes[@]}"; do
    read -r rc segundos < <(terminou "$nome")
    if [ "$rc" = 0 ]; then
      registrar conjuntas "${nome#conjuntas-}" passou "$segundos"
    else
      falhou=1
      registrar conjuntas "${nome#conjuntas-}" falhou "$segundos" "veja $PASTA/$nome.log"
    fi
  done
  if [ "$falhou" = 1 ]; then
    guardar_ambiente conjuntas
    for nome in "${nomes[@]}"; do
      read -r rc segundos < <(terminou "$nome")
      [ "$rc" = 0 ] || mostrar_falha "conjuntas/${nome#conjuntas-}" "$PASTA/$nome.log" "$PASTA/conjuntas-web-resultados" "$PASTA/conjuntas.servidor.log"
    done
  fi
  descer_ambiente conjuntas
}

echo "rodada em $PASTA"
case "$ALVO" in
  web) etapa_web ;;
  desktop) etapa_desktop ;;
  celular) etapa_celular ;;
  conjuntas) etapa_conjuntas ;;
  tudo)
    etapa_web
    etapa_desktop
    etapa_celular
    etapa_conjuntas
    ;;
esac

titulo "resultado"
column -t -s $'\t' "$RESULTADO"
if [ "$FALHAS" = 0 ] && [ -z "${CT_MANTER_PASTA:-}" ]; then
  rm -rf "$PASTA"
  echo "tudo passou; a pasta da rodada foi apagada"
else
  echo "pasta da rodada: $PASTA"
fi
[ "$FALHAS" = 0 ]
