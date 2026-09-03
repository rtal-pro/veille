#!/usr/bin/env bash
# La garde anti-redite de `nouveautes` : une URL déjà vue ne peut pas revenir.
# Prouvée par mutation — on la voit mordre, sinon elle n'est pas connue pour garder.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo "SKIP: docker unavailable"; exit 0; }

C=veille-nouveautes-test
docker rm -f $C >/dev/null 2>&1 || true
docker run -d --name $C -e POSTGRES_PASSWORD=t pgvector/pgvector:pg17 >/dev/null
trap 'docker rm -f $C >/dev/null' EXIT
until docker exec $C pg_isready -U postgres -q; do sleep 1; done
DB="postgresql://postgres:t@localhost:5432/postgres"
q() { docker exec $C psql "$DB" -tAc "$1"; }
for f in $(ls sql/*.sql | sort); do
  docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -1 -q -f - < "$f" \
    || { echo "FAIL: migration $f"; exit 1; }
done

U='https://www.producthunt.com/posts/exemple-anti-redite'
ins() {  # insère avec la clause exacte que le Kiosque utilisera, et rend
         # le NOMBRE de lignes réellement entrées (0 ou 1). Le CTE est
         # nécessaire : `psql -tAc` ajoute son tag « INSERT 0 1 » à la
         # sortie, donc compter les lignes du terminal compte le tag aussi.
  q "with i as (
       insert into nouveautes (terrain, nom, resume, url)
       values ('producthunt','Exemple','Un résumé bref.','$U')
       on conflict (url) do nothing returning 1)
     select count(*) from i"
}

# 1. Première récolte : la ligne entre.
[ "$(ins)" = "1" ] || { echo "FAIL: première insertion refusée"; exit 1; }

# 2. LA GARDE : deuxième récolte du même produit (il reste au classement PH
#    plusieurs jours) — rien ne doit entrer, et la table ne doit pas grossir.
[ "$(ins)" = "0" ] || { echo "FAIL: la même URL a été réinsérée — anti-redite absente"; exit 1; }
N=$(q "select count(*) from nouveautes where url='$U'")
[ "$N" = "1" ] || { echo "FAIL: $N lignes pour la même URL (want 1)"; exit 1; }

# 3. Mutation : sans ON CONFLICT, la contrainte doit MORDRE (et non passer).
if docker exec $C psql "$DB" -v ON_ERROR_STOP=1 -q -c \
     "insert into nouveautes (terrain, nom, resume, url)
      values ('appsumo','Exemple','x','$U')" >/dev/null 2>&1; then
  echo "FAIL: doublon accepté sans ON CONFLICT — la contrainte unique n'existe pas"; exit 1
fi

# 4. Le cycle d'annonce : NULL tant que non poussé, daté ensuite, et jamais repris.
[ "$(q "select count(*) from nouveautes where annonce_le is null")" = "1" ] \
  || { echo "FAIL: une nouveauté fraîche doit avoir annonce_le NULL"; exit 1; }
q "update nouveautes set annonce_le = current_date where annonce_le is null" >/dev/null
[ "$(q "select count(*) from nouveautes where annonce_le is null")" = "0" ] \
  || { echo "FAIL: l'UPDATE d'annonce n'a pas marqué la ligne"; exit 1; }

# 5. Idempotence : rejouer 009 ne doit ni dupliquer ni effacer.
docker exec -i $C psql "$DB" -v ON_ERROR_STOP=1 -1 -q -f - < sql/009_nouveautes.sql
[ "$(q "select count(*) from nouveautes")" = "1" ] \
  || { echo "FAIL: rejeu de 009 a modifié les données"; exit 1; }

echo "OK nouveautes"
