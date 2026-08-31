#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
S=scripts/porte_memo.sh
W=.github/workflows/veille-quotidienne.yml
m() { bash "$S" "$1"; }

# --- Contrat de la porte -----------------------------------------------------
# Cadence 2 passes (depuis le 2026-08-31) : 04:30 mémo + 15:00 filet. Les deux
# doivent pouvoir produire le mémo du jour ; c'est le garde deja_fait de la
# porte qui rétrograde la passe de 15:00 en récolte seule quand le mémo existe.
[ "$(m '30 4 * * *')" = "1" ] || { echo "FAIL memo 04:30"; exit 1; }
[ "$(m '0 15 * * *')" = "1" ] || { echo "FAIL filet 15:00 doit pouvoir rattraper le memo"; exit 1; }
[ "$(m '')"           = "1" ] || { echo "FAIL memo workflow_dispatch (schedule vide)"; exit 1; }
# Sécurité : un déclencheur inconnu retombe sur mémo (jamais un no-mémo silencieux)
[ "$(m 'weird cron')" = "1" ] || { echo "FAIL inconnu -> memo"; exit 1; }

# --- Test de DÉRIVE : workflow (config) <-> porte (script) -------------------
# La cadence vit en deux représentations. Un cron retiré du YAML mais laissé
# dans la liste noire du script transformerait silencieusement une future passe
# mémo en récolte — précisément le no-mémo silencieux que la porte dit éviter.
crons=$(grep -oE '^\s*- cron: "[^"]+"' "$W" | grep -oE '"[^"]+"' | tr -d '"')
n=$(printf '%s\n' "$crons" | grep -c .)
[ "$n" = "2" ] || { echo "FAIL cadence: $n crons declares dans le workflow, 2 attendus"; exit 1; }
while read -r c; do
  [ -n "$c" ] || continue
  [ "$(m "$c")" = "1" ] || { echo "FAIL cron '$c' declare dans le workflow mais degrade en recolte par la porte"; exit 1; }
done <<< "$crons"
# Toute entrée de la liste noire doit correspondre à un cron réellement déclaré.
deny=$(sed -n '/^  "/{s/).*//;s/^  //;p;}' "$S" | tr '|' '\n' | tr -d '"' || true)
while read -r d; do
  [ -n "$d" ] || continue
  printf '%s\n' "$crons" | grep -qxF "$d" || { echo "FAIL liste noire nomme '$d', absent du workflow (cron mort)"; exit 1; }
done <<< "$deny"
echo "OK porte_memo"
