#!/usr/bin/env bash
# Replays all migrations twice on a throwaway postgres:17, then a prod-like scenario.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f sql/000_legacy.sql ] || { echo "FAIL: sql/000_legacy.sql missing"; exit 1; }
command -v docker >/dev/null || { echo "SKIP: docker unavailable"; exit 0; }

C=veille-migtest
docker rm -f $C >/dev/null 2>&1 || true
docker run -d --name $C -e POSTGRES_PASSWORD=t pgvector/pgvector:pg17 >/dev/null
# pgvector image: 001 does `create extension vector` (absent from stock postgres:17)
# No host port is published: every psql call below runs via `docker exec` inside
# the container's own network namespace, where postgres listens on 5432 (not a
# host-mapped port). Publishing a host port is unnecessary and risks colliding
# with unrelated containers already bound to it on the dev machine.
trap 'docker rm -f $C >/dev/null' EXIT
until docker exec $C pg_isready -U postgres -q; do sleep 1; done
DB="postgresql://postgres:t@localhost:5432/postgres"
AGENT_DB="postgresql://agent_veille:t@localhost:5432/postgres"
run_all() { for f in $(ls sql/*.sql | sort); do
  docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -1 -q -f - < "$f" \
    || { echo "FAIL: $f (pass $1)"; exit 1; }
done; }

# agent_veille: created here (out-of-repo in real deploys) so 006's conditional
# grant/policy block actually exercises the role path instead of no-op'ing.
# Idempotent: the role is cluster-wide and survives the prod-scenario schema drop.
create_agent_role() {
  docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -q -c \
    "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'agent_veille') then create role agent_veille login password 't'; end if; end \$\$;"
}

# 006 must grant agent_veille just enough to work (SELECT/INSERT/UPDATE via a
# real RLS policy — not merely a bare, RLS-shadowed privilege) and no more
# (no DELETE grant): verify both sides of that gate.
assert_agent_role() {
  local label="$1" N NPOL
  # (a) SELECT must prove the POLICY, not just the grant: a bare privilege
  # with RLS default-deny still "succeeds" returning 0 rows, silently. Both
  # scenarios seed doctrine rows (001's constitution seed), so N=0 here means
  # the policy isn't effective even though the query raised no error.
  N=$(docker exec $C psql "$AGENT_DB" -v ON_ERROR_STOP=1 -tAc "select count(*) from doctrine" 2>&1) \
    || { echo "FAIL: agent_veille SELECT doctrine errored ($label): $N"; exit 1; }
  [ "$N" -gt 0 ] 2>/dev/null \
    || { echo "FAIL: agent_veille sees $N rows on doctrine via SELECT — RLS policy not effective ($label)"; exit 1; }
  # (b) Policy coverage: exactly the 13 tables carrying it — the 10 from 006
  # step 6, plus firecrawl_appels from 007, carte_produits from 008 and
  # nouveautes from 009. Any
  # future table added to the agent's reach must bump this number, which is the
  # point: a table granted without a policy is silently default-denied, a policy
  # without a grant is permission-denied, and only this count catches either.
  NPOL=$(docker exec $C psql "$DB" -tAc \
    "select count(*) from pg_policies where schemaname='public' and policyname='agent_veille_all'")
  [ "$NPOL" = "13" ] || { echo "FAIL: $NPOL agent_veille_all policies (want 13) ($label)"; exit 1; }
  docker exec $C psql "$AGENT_DB" -v ON_ERROR_STOP=1 -tAc \
    "insert into sources (url) values ('http://test-agent-$label')" >/dev/null \
    || { echo "FAIL: agent_veille cannot INSERT sources ($label)"; exit 1; }
  if docker exec $C psql "$AGENT_DB" -v ON_ERROR_STOP=1 -tAc "delete from doctrine" >/dev/null 2>&1; then
    echo "FAIL: agent_veille DELETE on doctrine should be denied ($label)"; exit 1
  fi
}

# 006 replaces moddatetime with an owned trigger function (set_updated_at):
# prove it fires on UPDATE, not just that it parses. The 1s sleep guarantees
# a detectable timestamp delta between the two separate psql invocations.
assert_updated_at_trigger() {
  local label="$1" before after
  before=$(docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -tAc \
    "insert into reserves (idee_id, question) values (null, 'trigger-check-$label') returning updated_at")
  sleep 1
  docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -q -c \
    "update reserves set statut = 'levee' where question = 'trigger-check-$label'"
  after=$(docker exec $C psql "$DB" -tAc \
    "select updated_at from reserves where question = 'trigger-check-$label'")
  [ "$before" != "$after" ] \
    || { echo "FAIL: reserves.updated_at trigger did not fire (before=$before after=$after) ($label)"; exit 1; }
}

create_agent_role
# Pass 1 (fresh) + pass 2 (idempotence): second pass must be a strict no-op on data
run_all 1
SNAP1=$(docker exec $C psql "$DB" -tAc "select count(*)||':'||coalesce(sum(id),0) from doctrine where statut='actif'")
run_all 2
SNAP2=$(docker exec $C psql "$DB" -tAc "select count(*)||':'||coalesce(sum(id),0) from doctrine where statut='actif'")
[ "$SNAP1" = "$SNAP2" ] || { echo "FAIL: doctrine changed on replay ($SNAP1 -> $SNAP2)"; exit 1; }
N=$(docker exec $C psql "$DB" -tAc "select count(*) from doctrine d where exists
     (select 1 from doctrine d2 where d2.id<d.id and md5(d2.regle)=md5(d.regle))")
[ "$N" = "0" ] || { echo "FAIL: $N duplicated doctrine rules"; exit 1; }
assert_agent_role fresh
assert_updated_at_trigger fresh

# Prod-like scenario: DB that already ran the OLD 001 (commit 3f8b0de) with live data
docker exec $C psql "$DB" -q -c "drop schema public cascade; create schema public;"
docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -q -f - < sql/000_legacy.sql
git show 3f8b0de:sql/001_init.sql | docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -q -f -
docker exec -i $C psql "$DB" -q <<'SQL'
insert into prospection_clones (clone_nom, statut_pipeline, verdict)
  values ('lead-vivant','lead','GO');           -- fresh Kiosque lead (phantom GO default)
insert into prospection_clones (clone_nom, statut_pipeline, verdict, statut_jambes)
  values ('go-historique','survivant','GO','{"trou_fr":{"statut":"PROUVÉ"}}');
SQL
# Reproduce the real prod constraint (verdict text not null default 'GO') so
# 006 step 3's drop-default / drop-not-null / purge ordering is actually
# exercised under test, not just tolerated after the fact. Both seeded rows
# already hold 'GO', so SET NOT NULL succeeds against live data.
docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -q -c \
  "alter table prospection_clones alter column verdict set default 'GO'; alter table prospection_clones alter column verdict set not null;"
create_agent_role
run_all prod
ST=$(docker exec $C psql "$DB" -tAc "select statut_pipeline||':'||coalesce(verdict,'NULL') from prospection_clones where clone_nom='lead-vivant'")
[ "$ST" = "lead:NULL" ] || { echo "FAIL: live lead was destroyed by replay (got $ST)"; exit 1; }
ST2=$(docker exec $C psql "$DB" -tAc "select statut_pipeline from prospection_clones where clone_nom='go-historique'")
[ "$ST2" = "survivant" ] || { echo "FAIL: historical survivor altered (got $ST2)"; exit 1; }
NPH=$(docker exec $C psql "$DB" -tAc "select count(*) from doctrine where statut='actif' and regle like 'Product Hunt%'")
[ "$NPH" = "1" ] || { echo "FAIL: $NPH active PH/HN rules (want 1)"; exit 1; }
assert_agent_role prod
echo "OK migrations"
