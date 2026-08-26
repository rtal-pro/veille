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
run_all() { for f in $(ls sql/*.sql | sort); do
  docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -1 -q -f - < "$f" \
    || { echo "FAIL: $f (pass $1)"; exit 1; }
done; }

# Pass 1 (fresh) + pass 2 (idempotence): second pass must be a strict no-op on data
run_all 1
SNAP1=$(docker exec $C psql "$DB" -tAc "select count(*)||':'||coalesce(sum(id),0) from doctrine where statut='actif'")
run_all 2
SNAP2=$(docker exec $C psql "$DB" -tAc "select count(*)||':'||coalesce(sum(id),0) from doctrine where statut='actif'")
[ "$SNAP1" = "$SNAP2" ] || { echo "FAIL: doctrine changed on replay ($SNAP1 -> $SNAP2)"; exit 1; }
N=$(docker exec $C psql "$DB" -tAc "select count(*) from doctrine d where exists
     (select 1 from doctrine d2 where d2.id<d.id and md5(d2.regle)=md5(d.regle))")
[ "$N" = "0" ] || { echo "FAIL: $N duplicated doctrine rules"; exit 1; }

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
run_all prod
ST=$(docker exec $C psql "$DB" -tAc "select statut_pipeline||':'||coalesce(verdict,'NULL') from prospection_clones where clone_nom='lead-vivant'")
[ "$ST" = "lead:NULL" ] || { echo "FAIL: live lead was destroyed by replay (got $ST)"; exit 1; }
ST2=$(docker exec $C psql "$DB" -tAc "select statut_pipeline from prospection_clones where clone_nom='go-historique'")
[ "$ST2" = "survivant" ] || { echo "FAIL: historical survivor altered (got $ST2)"; exit 1; }
NPH=$(docker exec $C psql "$DB" -tAc "select count(*) from doctrine where statut='actif' and regle like 'Product Hunt%'")
[ "$NPH" = "1" ] || { echo "FAIL: $NPH active PH/HN rules (want 1)"; exit 1; }
echo "OK migrations"
