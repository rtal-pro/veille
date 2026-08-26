#!/usr/bin/env bash
# Pure decision: is this trigger a MEMO pass (judge + email) or a HARVEST-only
# pass? No side effects, unit-testable (modèle : garde_fou_decide.sh).
# Usage: porte_memo.sh <schedule>
#   <schedule> : cron string of a `schedule` event (jq '.schedule' from the
#   event payload), or "" for workflow_dispatch / any trigger without a schedule.
# Echoes "1" (memo pass) or "0" (harvest-only pass).
#
# Harvest crons are an explicit DENYLIST; everything else — the 04:30 main memo
# cron, the 11:00 recovery cron, workflow_dispatch (empty schedule), and any
# unrecognised trigger — yields "1". Rationale: a stray extra memo is deduped
# downstream by the porte's deja_fait guard, whereas a silent NO-memo (e.g. a
# mistyped memo cron string) would go unnoticed.
set -euo pipefail
SCHED="${1:-}"
case "$SCHED" in
  "0 9 * * *"|"0 13 * * *"|"0 17 * * *") echo 0 ;;
  *) echo 1 ;;
esac
