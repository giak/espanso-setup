#!/usr/bin/env bash
# espanso-apply.sh — deploye les match files du depot vers la config runtime d'espanso.
#
# Le depot (match/) est la source de verite pour l'EDITION.
# ~/.config/espanso/match/ reste la source de verite pour l'EXECUTION : espanso ne lit que la.
# Ce script leve la desynchronisation en copiant le depot vers la config, apres validation.
#
# Usage :
#   ./scripts/espanso-apply.sh --check     # dry-run : affiche le diff, n'ecrit rien
#   ./scripts/espanso-apply.sh             # backup, copie, verifie
#   ./scripts/espanso-apply.sh --yes       # idem, sans confirmation
#
# Sort en 0 si la config runtime est alignee sur le depot apres coup, 1 sinon.

set -uo pipefail

RACINE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$RACINE/match"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/espanso/match"
SAUVEGARDE="$RACINE/.backup"
HORODATAGE="$(date +%Y-%m-%d-%H%M%S)"

dry_run=0
assume=0
for arg in "$@"; do
    case "$arg" in
        --check|-n) dry_run=1 ;;
        --yes|-y)   assume=1 ;;
        -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
        *) printf 'option inconnue : %s\n' "$arg" >&2; exit 2 ;;
    esac
done

ko=0
anomalie() { printf 'ANOMALIE  %s\n' "$1"; ko=1; }
info()     { printf 'info      %s\n' "$1"; }

[ -d "$SRC" ] || { printf 'ERREUR    %s absent\n' "$SRC" >&2; exit 2; }
mkdir -p "$DEST" || exit 2

# --- Inventaire des fichiers a deployer -----------------------------------------
mapfile -t fichiers < <(cd "$SRC" && find . -type f \( -name '*.yml' -o -name '*.yaml' \) | sed 's|^\./||' | sort)
[ "${#fichiers[@]}" -gt 0 ] || { printf 'ERREUR    aucun .yml dans %s\n' "$SRC" >&2; exit 2; }

# --- Validation avant toute ecriture --------------------------------------------
# Chaque fichier doit etre du YAML valide ; si le schema expose `matches:`, chaque
# entree doit avoir un `trigger` de type chaine, et les triggers doivent etre uniques.
valider() {
    local f="$1"
    if ! python3 - "$f" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("PyYAML absent : validation impossible"); sys.exit(3)
try:
    doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
except yaml.YAMLError as e:
    print(f"YAML invalide : {e}"); sys.exit(1)
if doc is None:
    sys.exit(0)
if not isinstance(doc, dict):
    print("la racine du document doit etre un mapping"); sys.exit(1)
matches = doc.get("matches")
if matches is None:
    sys.exit(0)
if not isinstance(matches, list):
    print("`matches` doit etre une liste"); sys.exit(1)
vus = set()
for i, m in enumerate(matches):
    if not isinstance(m, dict):
        print(f"matches[{i}] n'est pas un mapping"); sys.exit(1)
    t = m.get("trigger")
    if not isinstance(t, str) or not t:
        print(f"matches[{i}] : `trigger` absent ou non chaine"); sys.exit(1)
    if t in vus:
        print(f"trigger en double : {t!r}"); sys.exit(1)
    vus.add(t)
print(f"{len(matches)} match(es), {len(vus)} trigger(s) unique(s)")
PY
    then
        return 1
    fi
}

printf '== validation des sources ==\n'
valides=()
for rel in "${fichiers[@]}"; do
    if out=$(valider "$SRC/$rel"); then
        printf 'ok        %-28s %s\n' "$rel" "${out:-vide}"
        valides+=("$rel")
    else
        anomalie "$rel : $out"
    fi
done
[ "${#valides[@]}" -gt 0 ] || { printf '\nRESULTAT  aucune source valide, rien ecrit\n'; exit 1; }

# --- Ecarts a resoudre -----------------------------------------------------------
printf '\n== ecarts depot -> runtime ==\n'
a_copier=()
for rel in "${valides[@]}"; do
    if [ ! -e "$DEST/$rel" ]; then
        info "$rel : absent cote runtime, sera cree"
        a_copier+=("$rel"); continue
    fi
    if diff -q "$SRC/$rel" "$DEST/$rel" >/dev/null 2>&1; then
        printf 'ok        %-28s identique\n' "$rel"
    else
        info "$rel : DIFFERE"
        diff -u --label "depot/$rel" --label "runtime/$rel" "$DEST/$rel" "$SRC/$rel" | sed 's/^/          /'
        a_copier+=("$rel")
    fi
done

if [ "${#a_copier[@]}" -eq 0 ]; then
    printf '\nRESULTAT  deja aligne, rien a ecrire\n'
    exit 0
fi

if [ "$dry_run" -eq 1 ]; then
    printf '\nRESULTAT  dry-run, %d fichier(s) seraient copies\n' "${#a_copier[@]}"
    exit 0
fi

# --- Confirmation ---------------------------------------------------------------
printf '\n== deploiement ==\n'
if [ "$assume" -eq 0 ]; then
    printf 'Copier %d fichier(s) vers %s ? [o/N] ' "${#a_copier[@]}" "$DEST"
    read -r reponse
    case "$reponse" in [oOyY]*) ;; *) printf 'annule\n'; exit 0 ;; esac
fi

# --- Sauvegarde puis copie -------------------------------------------------------
for rel in "${a_copier[@]}"; do
    if [ -e "$DEST/$rel" ]; then
        mkdir -p "$SAUVEGARDE/$HORODATAGE/$(dirname "$rel")"
        cp -p "$DEST/$rel" "$SAUVEGARDE/$HORODATAGE/$rel"
        printf 'sauvegarde %s\n' "$SAUVEGARDE/$HORODATAGE/$rel"
    fi
    mkdir -p "$DEST/$(dirname "$rel")"
    install -m 644 "$SRC/$rel" "$DEST/$rel"
    printf 'ecrit     %s\n' "$DEST/$rel"
done

# --- Verification post-ecriture -------------------------------------------------
printf '\n== verification ==\n'
restant=0
for rel in "${valides[@]}"; do
    diff -q "$SRC/$rel" "$DEST/$rel" >/dev/null 2>&1 \
        && printf 'ok        %-28s aligne\n' "$rel" \
        || { anomalie "$rel toujours different"; restant=1; }
done

attendus=$(python3 - "$SRC" <<'PY'
import os, sys, yaml
total = 0
for root, _, names in os.walk(sys.argv[1]):
    for n in names:
        if not n.endswith((".yml", ".yaml")):
            continue
        doc = yaml.safe_load(open(os.path.join(root, n), encoding="utf-8")) or {}
        total += len(doc.get("matches") or []) if isinstance(doc, dict) else 0
print(total)
PY
)
charges=$(espanso match list 2>/dev/null | grep -c . || echo 0)
printf 'info      triggers dans le depot   : %s\n' "$attendus"
printf 'info      triggers charges par espanso : %s\n' "$charges"
[ "$charges" -eq "$attendus" ] \
    && printf 'ok        comptage concordant\n' \
    || anomalie "espanso charge $charges triggers, le depot en declare $attendus (paquets installs ?)"

if [ "$restant" -eq 0 ] && [ "$ko" -eq 0 ]; then
    printf '\nRESULTAT  config runtime alignee sur le depot\n'
else
    printf '\nRESULTAT  anomalies, voir ci-dessus\n'
fi
printf 'info      le worker recharge seul (--start-reason config_changed), pas de restart necessaire\n'
exit "$ko"