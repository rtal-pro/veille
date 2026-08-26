#!/usr/bin/env bash
# Pure decision logic for the Garde-fou — CONSTITUTIONAL FILE. No side effects,
# fully unit-testable. jq required (present on GitHub runners).
set -euo pipefail

AGENT_JOBS='["kiosque","prospecteur","instructeur","contre-avocat","rattrapage"]'

case "${1:?usage: qualifier <jobs.json> | decider <fails> <q1> <q2> <sha|-> <deja_reverte>}" in
  qualifier)
    # "agent" iff at least one first-line agent job failed after running >= 5 min
    # (a real execution failure). Fast failures (< 5 min) or email-only failures
    # have the infrastructure signature (OIDC, quota, auth, Gmail).
    jq -r --argjson A "$AGENT_JOBS" '
      [.jobs[] | select(.name as $n | $A | index($n))
               | select(.conclusion == "failure")
               | select(((.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601)) >= 300)]
      | if length > 0 then "agent" else "infra" end' "$2"
    ;;
  decider)
    FAILS=$2; Q1=$3; Q2=$4; COMMIT=${5:-}; DEJA=${6:-0}
    # Fail-safe: a revert gate must default to the SAFE action (noop) when the
    # failure count is missing or not a non-negative integer — never fall
    # through toward "revert". `[ "$FAILS" -lt 2 ]` on a non-numeric value
    # errors without aborting under set -e (arithmetic test failures inside
    # an if/elif condition don't trigger errexit), so guard explicitly first.
    case "$FAILS" in ''|*[!0-9]*) echo noop; exit 0;; esac
    if [ "$FAILS" -lt 2 ];                          then echo noop
    elif [ "$Q1" = infra ] || [ "$Q2" = infra ];    then echo alerte_infra
    elif [ -z "$COMMIT" ] || [ "$COMMIT" = "-" ];   then echo alerte_sans_merge
    elif [ "$DEJA" = "1" ];                         then echo alerte_deja_reverte
    else                                                 echo revert
    fi
    ;;
  *) echo "unknown subcommand: $1" >&2; exit 2;;
esac
