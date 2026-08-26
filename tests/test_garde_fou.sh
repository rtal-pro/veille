#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
S=scripts/garde_fou_decide.sh
q() { bash $S qualifier "tests/fixtures/gf/$1"; }
d() { bash $S decider "$@"; }
[ "$(q jobs_agent_fail.json)" = "agent" ]  || { echo "FAIL qualifier agent"; exit 1; }
[ "$(q jobs_infra_fail.json)" = "infra" ]  || { echo "FAIL qualifier infra"; exit 1; }
[ "$(q jobs_email_only.json)" = "infra" ]  || { echo "FAIL qualifier email-only"; exit 1; }
[ "$(q jobs_boundary_300.json)" = "agent" ] || { echo "FAIL qualifier boundary 300s (>=300 -> agent)"; exit 1; }
[ "$(q jobs_boundary_299.json)" = "infra" ] || { echo "FAIL qualifier boundary 299s (<300 -> infra)"; exit 1; }
[ "$(d 1 agent agent abc123 0)" = "noop" ]              || { echo "FAIL d1"; exit 1; }
[ "$(d 2 infra infra abc123 0)" = "alerte_infra" ]      || { echo "FAIL d2"; exit 1; }
[ "$(d 2 agent infra abc123 0)" = "alerte_infra" ]      || { echo "FAIL d3 (mixed=infra)"; exit 1; }
[ "$(d 2 agent agent '' 0)"     = "alerte_sans_merge" ] || { echo "FAIL d4"; exit 1; }
[ "$(d 2 agent agent abc123 1)" = "alerte_deja_reverte" ] || { echo "FAIL d5"; exit 1; }
[ "$(d 2 agent agent abc123 0)" = "revert" ]            || { echo "FAIL d6"; exit 1; }
# Regression: precedence pinning (missing-sha beats deja_reverte; infra beats everything)
[ "$(d 2 agent agent '' 1)"    = "alerte_sans_merge" ]  || { echo "FAIL d7 (missing-sha beats deja_reverte)"; exit 1; }
[ "$(d 2 agent agent - 1)"     = "alerte_sans_merge" ]  || { echo "FAIL d8 (sentinel '-' beats deja_reverte)"; exit 1; }
[ "$(d 2 infra infra '' 1)"    = "alerte_infra" ]       || { echo "FAIL d9 (infra beats missing-sha+deja)"; exit 1; }
# Regression: fail-safe on missing/non-numeric FAILS — must default to noop, never revert
[ "$(d 0 x x - 0)"             = "noop" ]               || { echo "FAIL d10 (fails<2 -> noop)"; exit 1; }
[ "$(d '' x x abc 0)"          = "noop" ]               || { echo "FAIL d11 (fails non-numeric -> noop, never revert)"; exit 1; }
echo "OK garde_fou"
