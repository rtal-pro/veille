-- ============================================================
-- Migration 004 — Mémoire interrogeable (le « RAG SQL » des agents)
-- Idempotente. Appliquée automatiquement par le workflow Setup.
-- ============================================================

-- Index plein-texte français sur les quatre mémoires
create index if not exists idx_runs_fts on veille_runs
  using gin (to_tsvector('french', coalesce(constats_methode,'') || ' ' || coalesce(notes,'')));
create index if not exists idx_naf_fts on carte_naf
  using gin (to_tsvector('french', coalesce(libelle,'') || ' ' || coalesce(notes,'')));
create index if not exists idx_sources_fts on sources
  using gin (to_tsvector('french', coalesce(nom,'') || ' ' || coalesce(notes,'') || ' ' || coalesce(type_preuve,'')));
create index if not exists idx_pc_memoire_fts on prospection_clones
  using gin (to_tsvector('french', coalesce(job_to_be_done,'') || ' ' || coalesce(clone_nom,'') || ' ' || coalesce(argument_decisif,'')));

-- LA fonction : tout ce que le système sait sur un sujet, en une requête.
-- Usage : SELECT * FROM memoire('experts comptables facturation');
create or replace function memoire(q text)
returns table(origine text, ref text, extrait text)
language sql stable as $$
  (select 'idée · ' || coalesce(verdict, statut_pipeline, 'lead'),
          clone_nom,
          left(coalesce(argument_decisif, job_to_be_done, ''), 200)
   from prospection_clones
   where to_tsvector('french', coalesce(job_to_be_done,'')||' '||coalesce(clone_nom,'')||' '||coalesce(argument_decisif,''))
         @@ plainto_tsquery('french', q)
   order by id desc limit 8)
  union all
  (select 'journal · ' || coalesce(agent,'?'),
          date_run::text,
          left(coalesce(constats_methode,'') || ' · ' || coalesce(notes,''), 200)
   from veille_runs
   where to_tsvector('french', coalesce(constats_methode,'')||' '||coalesce(notes,''))
         @@ plainto_tsquery('french', q)
   order by id desc limit 5)
  union all
  (select 'source · ' || statut,
          coalesce(nom, url),
          left(coalesce(notes,'') || ' · ' || coalesce(raison_statut,''), 200)
   from sources
   where to_tsvector('french', coalesce(nom,'')||' '||coalesce(notes,'')||' '||coalesce(type_preuve,''))
         @@ plainto_tsquery('french', q)
   order by id desc limit 5)
  union all
  (select 'secteur NAF · ' || statut,
          code || ' ' || libelle,
          left(coalesce(notes,''), 200)
   from carte_naf
   where to_tsvector('french', coalesce(libelle,'') || ' ' || coalesce(notes,''))
         @@ plainto_tsquery('french', q)
   limit 4)
$$;

-- Règle de doctrine associée
insert into doctrine (regle, origine) values
 ('Réflexe mémoire : avant d''explorer un sujet, un secteur, un outil ou une niche, interroger SELECT * FROM memoire(''mots clés'') — idées passées (et leurs verdicts), journaux, sources et carte NAF en une requête. Ce que le système sait déjà se relit, ne se redécouvre pas.', '2026-08-21 mémoire'),
 ('Plafond de doctrine : 25 règles actives maximum. Le Fossoyeur consolide au-delà (fusion des règles proches, absorbées passées en obsolete). Une doctrine trop longue n''est plus lue — la concision est une fonction de sécurité.', '2026-08-21 mémoire')
on conflict do nothing;

-- Vérification : select * from memoire('shopify conformité');
