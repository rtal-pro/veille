#!/usr/bin/env bash
# Pure decision: is this trigger a MEMO pass (judge + email) or a HARVEST-only
# pass? No side effects, unit-testable (modèle : garde_fou_decide.sh).
# Usage: porte_memo.sh <schedule>
#   <schedule> : cron string of a `schedule` event (jq '.schedule' from the
#   event payload), or "" for workflow_dispatch / any trigger without a schedule.
# Echoes "1" (memo pass) or "0" (harvest-only pass).
#
# Harvest crons are an explicit DENYLIST; everything else — the 04:30 main memo
# cron, the 15:00 safety-net cron, workflow_dispatch (empty schedule), and any
# unrecognised trigger — yields "1". Rationale: a stray extra memo is deduped
# downstream by the porte's deja_fait guard, whereas a silent NO-memo (e.g. a
# mistyped memo cron string) would go unnoticed.
set -euo pipefail
SCHED="${1:-}"
# La liste noire est VIDE sous la cadence 2 passes (04:30 mémo + 15:00 filet) :
# les deux crons déclarés doivent pouvoir produire le mémo du jour, et c'est le
# garde deja_fait de la porte qui rétrograde le filet en récolte seule une fois
# le mémo écrit. Le case est conservé : réintroduire une passe de récolte pure
# est un ajout d'une ligne, et tests/test_memo_porte.sh interdit d'y laisser un
# cron que le workflow ne déclare plus.
case "$SCHED" in
  *) echo 1 ;;
esac
