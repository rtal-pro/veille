-- ============================================================
-- Migration 008 — Cache Firecrawl : une page payée une seule fois
-- À exécuter après 007. Idempotente.
--
-- POURQUOI. Jusqu'ici le contenu rendu par Firecrawl était lu par l'agent,
-- résumé en deux lignes de `notes`, puis jeté avec le runner. La page était
-- donc rachetée à chaque fois qu'un agent y revenait — et ils y reviennent :
-- sur les 3 premiers jours, legifrance.gouv.fr a été tenté 3 fois par 3 agents
-- différents, Reddit à presque chaque run, economie.gouv.fr/dgccrf deux fois.
-- Un stock de crédits fini dépensé sur du contenu qu'on possédait déjà.
--
-- Cette table garde le corps de réponse brut. `scripts/fc.sh` la consulte
-- AVANT le plafond budgétaire : un appel servi par le cache coûte 0 crédit,
-- n'entame ni le budget du jour ni la réserve, et reste consultable en SQL —
-- donc une preuve peut être re-vérifiée sans repayer.
-- ============================================================

create table if not exists firecrawl_cache (
  cle text primary key,                      -- md5(endpoint | payload normalisé)
  endpoint text not null,                    -- search | map | scrape
  requete text,                              -- query ou URL, pour la lisibilité humaine
  contenu text not null,                     -- corps de réponse brut (JSON Firecrawl)
  octets integer not null default 0,
  credits_payes integer not null default 0,  -- ce qu'a coûté la première fois
  hits integer not null default 0,           -- combien de fois resservi gratuitement
  dernier_hit timestamptz,
  agent_origine text,
  expire_le date not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_firecrawl_cache_expire on firecrawl_cache (expire_le);

alter table firecrawl_cache enable row level security;

-- Ce que le cache a fait économiser, en crédits, depuis toujours.
create or replace view v_firecrawl_cache with (security_invoker = true) as
select
  endpoint,
  count(*)                                    as entrees,
  sum(hits)                                   as resservis,
  sum(hits * credits_payes)                   as credits_economises,
  pg_size_pretty(sum(octets)::bigint)         as poids,
  min(expire_le)                              as prochaine_purge
from firecrawl_cache
group by endpoint
order by credits_economises desc nulls last;

do $$ begin
  if exists (select 1 from pg_roles where rolname = 'agent_veille') then
    grant select, insert, update on firecrawl_cache to agent_veille;
    grant select on v_firecrawl_cache to agent_veille;
    drop policy if exists agent_veille_all on firecrawl_cache;
    create policy agent_veille_all on firecrawl_cache
      for all to agent_veille using (true) with check (true);
  end if;
end $$;

do $$ begin
  revoke all on v_firecrawl_cache from anon, authenticated;
exception when undefined_object then null; end $$;

-- Purge des entrées périmées. Elle vit ICI et pas dans fc.sh à dessein : le
-- rôle agent_veille n'a pas le DELETE (et ne doit pas l'avoir). Le job
-- `migrations` tourne avec le rôle propriétaire avant chaque passe du
-- pipeline, donc la purge passe plusieurs fois par jour, sans agent.
delete from firecrawl_cache where expire_le < current_date;

insert into doctrine (regle, origine) values
 ('Une page Firecrawl est payée UNE fois : `scripts/fc.sh` sert d''abord le cache (table firecrawl_cache), qui ne coûte aucun crédit et n''entame pas le budget du jour. Ne contourne jamais le cache pour « avoir du frais » — la fenêtre de fraîcheur est déjà dans sa durée de vie (3 jours pour /search, 14 pour /map et /scrape). Un besoin réellement frais et justifié : FC_NOCACHE=1, et dis pourquoi dans ton journal.', '2026-08-28 cache crédits')
on conflict do nothing;

-- Vérification : select * from v_firecrawl_cache;
