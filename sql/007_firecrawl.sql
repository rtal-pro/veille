-- ============================================================
-- Migration 007 — Comptabilité Firecrawl (grand livre + plafond partagé)
-- À exécuter après 006. Idempotente.
--
-- POURQUOI. Jusqu'ici Firecrawl n'avait qu'un garde-fou : une phrase de la
-- constitution (« règle d'or crédits : ~33/jour »). Or le pipeline lance 8 à
-- 12 PROCESSUS D'AGENTS INDÉPENDANTS par jour (4 passes de récolte × kiosque
-- + prospecteur, puis le jugement, le tout doublé les lendemains de jour
-- rouge). Chaque agent respectait consciencieusement « son » budget dans son
-- coin ; personne ne comptait le total ; aucune ligne n'était journalisée.
-- Un budget par run dans un système multi-processus n'est pas un budget.
-- Résultat mesuré sur les 3 premiers jours (26→28/08/2026) : la moitié du
-- stock gratuit consommée, et impossible de dire à quoi — les seules traces
-- étaient `veille_runs.metriques.requetes_web`, qui agrège indistinctement
-- WebSearch, WebFetch, curl et Firecrawl, plus quelques mentions en texte
-- libre dans `incidents`.
--
-- Cette table est le grand livre : une ligne par appel Firecrawl, avec son
-- coût réel. `scripts/fc.sh` l'écrit et s'en sert comme compteur partagé
-- pour refuser un appel au-delà du plafond du jour.
-- ============================================================

create table if not exists firecrawl_appels (
  id bigint generated always as identity primary key,
  date_run date not null default current_date,
  agent text not null,                       -- kiosque, prospecteur, instructeur…
  endpoint text not null,                    -- search | map | scrape
  requete text,                              -- query ou URL (tronquée à 500)
  credits integer not null default 0,        -- coût réel de CET appel
  credits_restants integer,                  -- solde live renvoyé par Firecrawl après l'appel
  source_cout text not null default 'bareme',-- 'delta' (mesuré) | 'bareme' (estimé)
  http_status integer,
  refuse boolean not null default false,     -- appel bloqué par le plafond (coût 0, trace gardée)
  motif text,                                -- si refusé : pourquoi
  run_id text,                               -- GITHUB_RUN_ID, pour recoller au log Actions
  created_at timestamptz not null default now()
);

create index if not exists idx_firecrawl_appels_jour on firecrawl_appels (date_run desc, agent);

alter table firecrawl_appels enable row level security;

-- Vue de lecture : « à quoi sont partis les crédits », par jour et par agent.
-- C'est la réponse à la question qu'on ne pouvait pas poser avant.
create or replace view v_firecrawl_jour with (security_invoker = true) as
select
  date_run,
  agent,
  endpoint,
  count(*) filter (where not refuse)                             as appels,
  count(*) filter (where refuse)                                 as refuses,
  coalesce(sum(credits) filter (where not refuse), 0)            as credits,
  min(credits_restants) filter (where credits_restants is not null) as solde_min
from firecrawl_appels
group by date_run, agent, endpoint
order by date_run desc, credits desc;

-- Grants + policy pour le rôle restreint (même contrat que 006 : SELECT/
-- INSERT/UPDATE, jamais DELETE, jamais DDL). Le GRANT sur les séquences est
-- re-joué ici : celui de 006 est une photographie ponctuelle et ne couvre
-- pas la séquence d'identité créée ci-dessus.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'agent_veille') then
    grant select, insert, update on firecrawl_appels to agent_veille;
    grant select on v_firecrawl_jour to agent_veille;
    grant usage, select on all sequences in schema public to agent_veille;
    drop policy if exists agent_veille_all on firecrawl_appels;
    create policy agent_veille_all on firecrawl_appels
      for all to agent_veille using (true) with check (true);
  end if;
end $$;

do $$ begin
  revoke all on v_firecrawl_jour from anon, authenticated;
exception when undefined_object then null; end $$;

-- Doctrine : la règle devient vérifiable, plus déclarative.
insert into doctrine (regle, origine) values
 ('Firecrawl passe EXCLUSIVEMENT par scripts/fc.sh (search|map|scrape). Un curl direct sur api.firecrawl.dev est une infraction : il ne consomme pas moins de crédits, il les consomme sans trace et sans plafond. fc.sh refuse (exit 3) au-delà du plafond partagé du jour — un refus n''est PAS une panne : retombe sur WebSearch/WebFetch/curl gratuit et continue.', '2026-08-28 comptabilité crédits'),
 ('Le budget Firecrawl est GLOBAL au jour, pas par run : le pipeline lance 8 à 12 agents indépendants par jour. Aucun agent ne peut donc juger son propre budget « raisonnable » — seul le compteur partagé (firecrawl_appels) fait foi. Vérifier son solde avec `scripts/fc.sh solde` AVANT de planifier une stratégie de recherche large.', '2026-08-28 comptabilité crédits'),
 ('Priorité d''usage des crédits Firecrawl, du plus au moins rentable : (1) /scrape d''une page à anti-bot qui bloque une PREUVE déjà identifiée — 1 crédit pour débloquer une jambe ; (2) /map d''un gisement déjà qualifié — 1 crédit pour des centaines d''URLs ; (3) /search de découverte large — 2 crédits et plus, à ne dépenser que si WebSearch a déjà échoué sur le même angle. La découverte large en premier réflexe est le mode de consommation qui a vidé la moitié du stock en 3 jours.', '2026-08-28 comptabilité crédits')
on conflict do nothing;

-- Vérification : select * from v_firecrawl_jour;
