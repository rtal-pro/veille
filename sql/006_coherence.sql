-- ============================================================
-- Migration 006 — Cohérence pipeline + sécurité des accès.
-- Idempotente (marqueurs one-shot pour les updates de données).
-- ============================================================

-- 1. Discriminant mémo quotidien / digest hebdo
alter table verdicts add column if not exists type text not null default 'quotidien';
do $$ begin
  alter table verdicts add constraint verdicts_type_chk
    check (type in ('quotidien','hebdo'));
exception when duplicate_object then null; end $$;

-- 2. v_sante_pipeline lit le jour_rouge du mémo QUOTIDIEN uniquement
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
     where vv.date_run = j.jour and vv.type = 'quotidien'
     order by vv.id desc limit 1)                                                                              as jour_rouge
from jours j
order by j.jour desc;

-- 3. Fin du « GO par défaut » : un lead non instruit n'a PAS de verdict
alter table prospection_clones alter column verdict drop default;
alter table prospection_clones alter column verdict drop not null;
do $$
begin
  if not exists (select 1 from migrations_appliquees where nom = '006-purge-verdicts-fantomes') then
    update prospection_clones set verdict = null
      where statut_pipeline = 'lead' and statut_jambes is null;
    insert into migrations_appliquees (nom) values ('006-purge-verdicts-fantomes');
  end if;
end $$;

-- 4. Lexique d'états verrouillé (valeurs prod vérifiées le 2026-08-26)
do $$ begin
  alter table prospection_clones add constraint pc_statut_pipeline_chk
    check (statut_pipeline in ('lead','en_file','survivant','ecarte','tue')) not valid;
exception when duplicate_object then null; end $$;
alter table prospection_clones validate constraint pc_statut_pipeline_chk;

-- 5. reserves.updated_at maintenu automatiquement
create extension if not exists moddatetime;
drop trigger if exists reserves_updated_at on reserves;
create trigger reserves_updated_at before update on reserves
  for each row execute function moddatetime(updated_at);

-- 6. Accès du rôle agent (créé hors repo, au déploiement) — gabarit pour
--    toute migration future : ajouter ici les nouvelles tables.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'agent_veille') then
    grant usage on schema public to agent_veille;
    grant select, insert, update on
      prospection_clones, veille_runs, analyses_go,
      sources, carte_naf, reserves, doctrine, verdicts,
      audits, modifications
      to agent_veille;
    grant select on v_sante_pipeline, sante_agents to agent_veille;
    grant usage, select on all sequences in schema public to agent_veille;
    -- No DELETE, no TRUNCATE, no DDL: a prompt-injected agent cannot destroy memory.
  end if;
end $$;

-- 7. Pas d'exposition PostgREST anonyme des vues (anon/authenticated
--    n'existent que sur Supabase, d'où la garde)
do $$ begin
  revoke all on v_sante_pipeline, sante_agents from anon, authenticated;
exception when undefined_object then null; end $$;
