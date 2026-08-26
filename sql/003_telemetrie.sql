-- ============================================================
-- Migration 003 — Télémétrie + monitoring du Superviseur
-- À exécuter après 001 et 002. Idempotente.
-- ============================================================

-- 1. Télémétrie structurée par run (contrat commun à tous les agents)
alter table veille_runs add column if not exists metriques jsonb;
-- Clés minimales attendues : {"insertions":N,"updates":N,"requetes_web":N,"incidents":["..."]}

-- 2. Idempotence de la doctrine (rend les INSERT ... ON CONFLICT réellement sûrs)
create unique index if not exists idx_doctrine_unique on doctrine (md5(regle));

-- 3. Vue de santé : 14 jours d'un coup pour le Superviseur et la Lectrice
create or replace view v_sante_pipeline with (security_invoker = true) as
with jours as (
  select generate_series(current_date - 13, current_date, interval '1 day')::date as jour
)
select
  j.jour,
  (select count(*) from prospection_clones p where p.date_run = j.jour)                                        as leads_reels,
  (select coalesce(sum(v.candidats_inseres),0) from veille_runs v where v.date_run = j.jour)                   as inserts_declares,
  (select count(*) from prospection_clones p where p.date_run = j.jour and p.statut_pipeline = 'survivant')    as survivants_du_cru,
  (select coalesce(sum(v.dont_go),0) from veille_runs v
     where v.date_run = j.jour and v.agent in ('contre-avocat','rattrapage'))                                  as go_declares,
  (select count(distinct v.agent) from veille_runs v where v.date_run = j.jour)                                as agents_journalises,
  (select (vv.stats->>'jour_rouge')::boolean from verdicts vv
     where vv.date_run = j.jour order by vv.id desc limit 1)                                                   as jour_rouge
from jours j
order by j.jour desc;
-- Note : survivants_du_cru = statut ACTUEL des leads insérés ce jour-là (approximation
-- honnête, un lead peut survivre un autre jour que son insertion). L'écart entre
-- leads_reels et inserts_declares est le premier test anti-mensonge de la télémétrie.

-- 4. Règles de doctrine associées
insert into doctrine (regle, origine) values
 ('Télémétrie obligatoire : chaque journal de fin de run remplit AUSSI la colonne metriques (jsonb), au minimum {"insertions":N,"updates":N,"requetes_web":N,"incidents":[]}. Le Superviseur recoupe ces déclarations avec les comptages réels (v_sante_pipeline) : un écart répété est traité comme un bug de l''agent, prioritaire.', '2026-08-21 télémétrie'),
 ('Communautés : un forum public, un subreddit ou une issue GitHub prouvent la DOULEUR et fournissent le vocabulaire métier — jamais la WTP ni le canal. Toute preuve doit être une URL publique lisible sans connexion : Facebook, Discord et Slack privés sont des pistes à re-sourcer ailleurs, jamais des preuves.', '2026-08-21 communautés')
on conflict do nothing;

-- Views bypass table RLS unless security_invoker; belt-and-braces for PostgREST.
do $$ begin
  revoke all on v_sante_pipeline, sante_agents from anon, authenticated;
exception when undefined_object then null; end $$;

-- Vérification : select * from v_sante_pipeline;
