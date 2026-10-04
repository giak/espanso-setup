#!/usr/bin/env bash
# espanso-check.sh — état de santé déterministe de l'installation espanso.
# Sort en 0 si tout est conforme, en 1 sinon. Sans effet de bord.

set -uo pipefail

VERSION_ATTENDUE="2.4.1"
BIN_ATTENDU="/usr/bin/espanso"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/espanso"

ko=0
anomalie() { printf 'ANOMALIE  %s\n' "$1"; ko=1; }
ok()      { printf 'ok        %s\n' "$1"; }
info()    { printf 'info      %s\n' "$1"; }

printf '== binaire ==\n'
if command -v espanso >/dev/null 2>&1; then
  resolved=$(readlink -f "$(command -v espanso)")
    v=$(espanso --version 2>/dev/null | head -1)
    if [ "$resolved" = "$BIN_ATTENDU" ]; then
        ok "espanso -> $resolved (instance unique)"
    else
        anomalie "espanso résout vers $resolved, attendu $BIN_ATTENDU"
    fi
    if [ "$v" = "$VERSION_ATTENDUE" ]; then
        ok "version $v"
    else
        anomalie "version $v, attendue $VERSION_ATTENDUE"
    fi
    pkg=$(dpkg-query -W -f='${Version}' espanso 2>/dev/null)
    if [ -n "$pkg" ]; then
        ok "paquet dpkg espanso $pkg"
    else
        info "aucun paquet dpkg espanso (install hors apt ?)"
    fi
else
    anomalie "commande espanso introuvable"
fi

printf '== service systemd ==\n'
act=$(systemctl --user is-active espanso 2>/dev/null)
en=$(systemctl --user is-enabled espanso 2>/dev/null)
[ "$act" = "active" ] && ok "service active" || anomalie "service $act"
[ "$en" = "enabled" ] && ok "service enabled au démarrage" || info "service $en"
unit=$(systemctl --user show espanso -p ExecStart --value 2>/dev/null)
case "$unit" in
    *"$BIN_ATTENDU"*) ok "ExecStart pointe $BIN_ATTENDU" ;;
    *)                anomalie "ExecStart: $unit" ;;
esac

printf '== processus ==\n'
nb_daemon=$(pgrep -fc 'espanso daemon' 2>/dev/null || echo 0)
nb_worker=$(pgrep -fc 'espanso worker' 2>/dev/null || echo 0)
nb_zomb=$(ps -eo stat,cmd 2>/dev/null | grep -c '^Z.*espanso')
[ "$nb_daemon" -ge 1 ] && ok "daemon présent ($nb_daemon)" || anomalie "aucun daemon"
[ "$nb_worker" -ge 1 ] && ok "worker présent ($nb_worker)" || anomalie "aucun worker"
[ "$nb_zomb" -eq 0 ] && ok "aucun processus zombie" || anomalie "$nb_zomb processus zombie(s)"

printf '== configuration ==\n'
if [ -f "$CONFIG/config/default.yml" ]; then
    ok "default.yml présent"
    delay=$(awk '/^inject_delay:/ {print $2}' "$CONFIG/config/default.yml")
    if [ -z "$delay" ] || [ "$delay" = "null" ]; then
        anomalie "inject_delay absent ou null : l'injection X11 part sans délai,"
        anomalie "  les caracteres sont melanges dans les apps Electron (Chromium)"
    else
        ok "inject_delay = $delay ms"
    fi
    layout=$(awk '/^[[:space:]]+layout:/ {print $2; exit}' "$CONFIG/config/default.yml")
    [ -n "$layout" ] && ok "keyboard_layout = $layout" || info "keyboard_layout non renseigne"
    stale=$(grep -cE '^[^#]*:\s*null\s*$' "$CONFIG/config/default.yml")
    info "$stale option(s) a null (normal : non requis = valeur par defaut)"
else
    anomalie "default.yml absent ($CONFIG)"
fi

printf '== triggers ==\n'
if out=$(espanso match list 2>/dev/null); then
    n=$(printf '%s\n' "$out" | grep -c .)
    [ "$n" -ge 1 ] && ok "$n trigger(s) charge(s)" || anomalie "aucun trigger charge"
    drift=0
    if [ -f match/base.yml ] && [ -f "$CONFIG/match/base.yml" ]; then
        diff -q match/base.yml "$CONFIG/match/base.yml" >/dev/null 2>&1 || drift=1
    fi
    [ "$drift" -eq 0 ] && ok "match/base.yml du depot identique a la config runtime" \
                       || anomalie "match/base.yml du repo diverge de $CONFIG/match/base.yml"
else
    anomalie "espanso match list a echoue : le daemon repond-il ?"
fi

printf '== journal ==\n'
if espanso status 2>/dev/null | grep -q running; then
    ok "espanso status : running"
else
    anomalie "espanso status : $(espanso status 2>&1)"
fi
if command -v espanso >/dev/null 2>&1; then
    errs=$(espanso log 2>/dev/null | grep -cE '\[ERROR\]|panic')
    warn=$(espanso log 2>/dev/null | grep -c '\[WARN\]')
    [ "$errs" -eq 0 ] && ok "0 ERROR dans le log" || info "$errs ERROR historique(s) dans le log (voir espanso log)"
    [ "$warn" -eq 0 ] || info "$warn WARN dans le log"
    prov=$(espanso log 2>/dev/null | grep -oE 'using X11[A-Za-z]+' | tail -4 | tr '\n' ' ')
    [ -n "$prov" ] && info "providers : $prov"
fi

printf '\n'
if [ "$ko" -eq 0 ]; then
    printf 'RESULTAT  OK\n'
else
    printf 'RESULTAT  ANOMALIES DETECTEES\n'
fi
exit "$ko"