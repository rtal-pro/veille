#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
S=scripts/porte_memo.sh
m() { bash "$S" "$1"; }
# Passes MÉMO (jugement + email)
[ "$(m '30 4 * * *')" = "1" ] || { echo "FAIL memo 04:30"; exit 1; }
[ "$(m '0 11 * * *')" = "1" ] || { echo "FAIL memo 11:00 reprise"; exit 1; }
[ "$(m '')"           = "1" ] || { echo "FAIL memo workflow_dispatch (schedule vide)"; exit 1; }
# Passes RÉCOLTE seule
[ "$(m '0 9 * * *')"  = "0" ] || { echo "FAIL recolte 09:00"; exit 1; }
[ "$(m '0 13 * * *')" = "0" ] || { echo "FAIL recolte 13:00"; exit 1; }
[ "$(m '0 17 * * *')" = "0" ] || { echo "FAIL recolte 17:00"; exit 1; }
# Sécurité : un déclencheur inconnu retombe sur mémo (jamais un no-mémo silencieux)
[ "$(m 'weird cron')" = "1" ] || { echo "FAIL inconnu -> memo"; exit 1; }
echo "OK porte_memo"
