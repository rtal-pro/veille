#!/usr/bin/env bash
# Pure decision logic for the Garde-fou — CONSTITUTIONAL FILE. No side effects,
# fully unit-testable. jq required (present on GitHub runners).
set -euo pipefail

AGENT_JOBS='["kiosque","prospecteur","instructeur","contre-avocat","rattrapage"]'

case "${1:?usage: qualifier <jobs.json> | decider <fails> <q1> <q2> <sha|-> <deja_reverte>}" in
  qualifier)
    # A PARTIAL pass — a harvest-only cron (memo=0), or the 11:00 recovery when
    # the day's memo already exists (deja_fait=1) — skips the judgment jobs, so
    # `instructeur` reports "skipped". Such a run is not a full-pipeline
    # traversal: kiosque/prospecteur failing there says nothing about a
    # judgment-side commit, so it must NOT count toward a revert. Detected first,
    # before the agent/infra split (and before the date arithmetic below, which
    # a skipped job's null timestamps would otherwise choke on).
    if [ "$(jq -r '[.jobs[] | select(.name=="instructeur") | .conclusion] | first // ""' "$2")" = "skipped" ]; then
      echo partiel; exit 0
    fi
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
    # A revert requires TWO full-pipeline agent failures. If either counted
    # failure was a PARTIAL run (harvest-only / recovery — see qualifier), we do
    # not have two full traversals: alert, never revert. Checked before infra so
    # a partial run can never be mistaken for a revert-worthy full failure.
    if [ "$FAILS" -lt 2 ];                           then echo noop
    elif [ "$Q1" = partiel ] || [ "$Q2" = partiel ]; then echo alerte_recolte
    elif [ "$Q1" = infra ] || [ "$Q2" = infra ];     then echo alerte_infra
    elif [ -z "$COMMIT" ] || [ "$COMMIT" = "-" ];   then echo alerte_sans_merge
    elif [ "$DEJA" = "1" ];                         then echo alerte_deja_reverte
    else                                                 echo revert
    fi
    ;;
  *) echo "unknown subcommand: $1" >&2; exit 2;;
esac
