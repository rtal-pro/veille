-- ============================================================
-- Migration 001 — Système de veille v1 (GitHub Actions)
-- Exécutée via setup.yml / le job migrations, après 000_legacy.sql.
-- Idempotente : rejouable sans casse (dépend de migrations_appliquees, posée par 000).
-- ============================================================

-- Extensions (dédup gratuite : trigrammes + FTS français ; pas d'embeddings payants)
create extension if not exists pg_trgm;
-- pgvector prêt si un jour tu ajoutes une API d'embeddings (optionnel, inutilisé en v1) :
create extension if not exists vector;

-- ------------------------------------------------------------
-- 1. Nouvelles tables
-- ------------------------------------------------------------

create table if not exists sources (
  id bigint generated always as identity primary key,
  url text not null unique,
  nom text,
  type_preuve text,              -- ex: 'avis app store', 'MRR publié', 'texte réglementaire', 'presse pro'
  decouverte_via text,           -- généalogie : 'seed', 'kiosque: <url>', 'prospecteur:NAF 8121Z'
  statut text not null default 'candidate'
    check (statut in ('candidate','active','enterree','bannie')),
  score numeric,                 -- 1-5, rendement réel (Fossoyeur)
  raison_statut text,            -- obligatoire quand enterree/bannie
  derniere_visite timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists carte_naf (
  code text primary key,         -- ex: '62.01Z'
  libelle text not null,
  statut text not null default 'vierge'
    check (statut in ('vierge','exploree','sterile','riche')),
  date_exploration date,
  notes text
);

create table if not exists reserves (
  id bigint generated always as identity primary key,
  idee_id bigint references prospection_clones(id),
  question text not null,        -- la réserve, formulée en question testable
  protocole text,                -- comment la lever (recherche / landing+ads / appel)
  statut text not null default 'a_tester'
    check (statut in ('a_tester','levee','confirmee','attend_humain')),
  resultat text,
  url_preuve text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists doctrine (
  id bigint generated always as identity primary key,
  regle text not null,
  origine text,                  -- d'où vient la règle (run, date)
  statut text not null default 'actif' check (statut in ('actif','obsolete')),
  created_at timestamptz not null default now()
);

create table if not exists verdicts (
  id bigint generated always as identity primary key,
  date_run date not null,
  memo_md text,
  go_du_jour text[],
  stats jsonb,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. Évolutions des tables existantes
-- ------------------------------------------------------------

alter table prospection_clones
  add column if not exists statut_pipeline text default 'lead',
  add column if not exists source_id bigint references sources(id),
  add column if not exists condition_resurrection text,
  add column if not exists rapport_attaque text,
  add column if not exists score_atelier jsonb;

alter table veille_runs
  add column if not exists agent text,
  add column if not exists metriques jsonb;

-- Tableau de bord du Superviseur (et de la Lectrice) : santé de chaque agent sur 7 jours
create or replace view sante_agents with (security_invoker = true) as
select
  agent,
  max(date_run)                                              as dernier_run,
  count(*) filter (where date_run >= current_date - 7)       as runs_7j,
  coalesce(sum(candidats_inseres) filter (where date_run >= current_date - 7), 0) as candidats_7j,
  coalesce(sum(dont_go) filter (where date_run >= current_date - 7), 0)           as go_7j,
  count(*) filter (where date_run >= current_date - 7
                   and metriques->>'budget_respecte' = 'false')                    as depassements_7j,
  count(*) filter (where date_run >= current_date - 7
                   and jsonb_typeof(metriques->'incidents') = 'array'
                   and jsonb_array_length(metriques->'incidents') > 0)    as runs_avec_erreurs_7j
from veille_runs
where agent is not null
group by agent;

-- Index de dédup (similarité de nom + recherche plein-texte française sur le JTBD)
create index if not exists idx_pc_nom_trgm
  on prospection_clones using gin (clone_nom gin_trgm_ops);
create index if not exists idx_pc_jtbd_fts
  on prospection_clones using gin (to_tsvector('french', coalesce(job_to_be_done,'') || ' ' || coalesce(clone_nom,'')));
create index if not exists idx_pc_pipeline on prospection_clones (statut_pipeline);

-- ------------------------------------------------------------
-- 3. Backfill des lignes historiques — ONE-SHOT (migrations_appliquees).
--    Une base backfillée avant l'introduction du marqueur (la prod)
--    est détectée par la présence d'états post-backfill : on pose
--    alors le marqueur SANS retoucher les données vivantes.
-- ------------------------------------------------------------

do $$
begin
  if not exists (select 1 from migrations_appliquees where nom = '001-backfill') then
    if not exists (select 1 from prospection_clones
                   where statut_pipeline in ('survivant','ecarte','tue','en_file')) then
      update prospection_clones set statut_pipeline =
        case verdict
          when 'GO' then 'survivant'
          when 'GO sous réserve' then 'survivant'
          else 'ecarte'
        end
      where statut_pipeline = 'lead' or statut_pipeline is null;

      insert into reserves (idee_id, question, protocole, statut)
      select id,
             coalesce(risque_principal, 'Réserve non explicitée — relire la fiche'),
             'À définir par l''Instructeur : vérifier par recherche sourcée ; si test réel requis (landing+ads), passer en attend_humain.',
             'a_tester'
      from prospection_clones
      where verdict = 'GO sous réserve'
        and not exists (select 1 from reserves r where r.idee_id = prospection_clones.id);
    end if;
    insert into migrations_appliquees (nom) values ('001-backfill');
  end if;
end $$;

-- ------------------------------------------------------------
-- 4. Seed doctrine (apprentissages PROUVÉS des runs d'août 2026)
-- ------------------------------------------------------------

-- Idempotence du seed : dédoublonnage puis arbitre d'unicité (md5, aligné 003)
delete from doctrine a using doctrine b
  where md5(a.regle) = md5(b.regle) and a.id > b.id;
drop index if exists idx_doctrine_regle;      -- old btree-on-text index (prod)
create unique index if not exists idx_doctrine_unique on doctrine (md5(regle));

-- La règle PH/HN a été réécrite : rendre l'ancienne version obsolète
-- (ancrage exact md5 sur le texte de 3f8b0de, PAS un préfixe LIKE qui
--  basculerait aussi toute future règle commençant pareil)
update doctrine set statut = 'obsolete'
  where statut = 'actif'
    and md5(regle) = md5('Product Hunt / Hacker News en flux généraliste = stérile pour du vertical clonable (documenté 4 runs sur 5). Admissible uniquement en pointant un produit précis depuis une autre source.');

insert into doctrine (regle, origine) values
 ('Trou FR d''abord : vérifier concurrents FR / fonction native / substitut gratuit AVANT toute instruction de traction étrangère. ~37 % des écartés historiques meurent là.', 'analyse base 2026-08-20'),
 ('Aucun chiffre sans URL lue. Chiffres de listicles (flowjam, vibrantsnap, tamimbuilds…) = À BANNIR, invérifiables.', 'run 2026-08-03'),
 ('Conformité UE : une source DACH/Benelux/nordique/UK vaut plus qu''une source US (obligation identique). Ordre : (1) DACH/Benelux/nordiques/UK (2) US (3) JP/KR/CA/AU inspiration (4) CN pattern d''usage.', 'run 2026-08-03 constat 7'),
 ('Avant de cloner un modèle étranger, vérifier que la France n''est pas déjà le marché le plus avancé sur le créneau (cas ställplatser/Camping-Car Park).', 'run 2026-08-03 constat 8'),
 ('Une source nordique prouve un MÉCANISME, pas la transposabilité (Swish/Vipps + BankID = artefacts d''infrastructure nationale).', 'run 2026-08-03 constat 9'),
 ('Une obligation réglementaire prouve la jambe trou_fr, JAMAIS la jambe canal. Sans canal self-serve identifiable, pas de GO.', 'run 2026-08-03 constat 2'),
 ('Kill immédiat (vague 0) : logiciel de caisse (NF525/LNE), données de santé (HDS), activités à agrément préalable (ex. NEPH).', 'écartés août 2026'),
 ('Shopify absorbe les fonctions de conformité d''affichage (ex. prix barré Omnibus devenu natif) : toute app de conformité affichage se vend en bundle, jamais en fonction unique.', 'run 2026-08-03 constat 4'),
 ('Catégories bannies (saturées/refutées, ne pas re-fouiller) : accessibilité Shopify (~120 apps) ; Omnibus prix 30j ; points relais ; passeport produit DPP (demande nulle constatée) ; collecte de documents clients FR (Doccollect, Superdocu, Wizidee, Clustdoc) ; extraction relevés bancaires (Parseur) ; résumé IA d''avis clients Shopify/Woo (≥5 acteurs) ; order printer/pick lists Shopify ; AI executive assistant généraliste ; lien-en-bio ; GEO/AI-visibility tracker (doublon id 196).', 'runs 2026-08-03→15'),
 ('Règle de proximité : candidat très proche d''une idée déjà écartée = écart. Doute = écart.', 'runs août 2026'),
 ('Product Hunt / Hacker News : jamais en gisement principal (flux généraliste ≈ 95 % de bruit, documenté 4 runs sur 5), mais toujours en SAS DE NOUVEAUTÉ plafonné à 5 min : scan titres seulement, filtre vertical/B2B, détection de convergences (2+ lancements même JTBD la même semaine = signal de douleur). 2 des 13 GO historiques en viennent.', 'runs août 2026 + correction 2026-08-20'),
 ('Le rendement vient des sources à PREUVE CHIFFRÉE LISIBLE : fiches d''app stores (avis, prix, langue, date), interviews à MRR publié, textes officiels.', 'run 2026-08-03 constat 1')
on conflict do nothing;

-- ------------------------------------------------------------
-- 5. Seed sources (rendement déjà observé dans tes runs)
-- ------------------------------------------------------------

insert into sources (url, nom, type_preuve, decouverte_via, statut, score, notes) values
 ('https://apps.shopify.com', 'Shopify App Store', 'avis, prix, langue, date des fiches', 'seed (runs août)', 'active', 5, 'TRÈS PRODUCTIF historiquement (3 des 5 premiers GO). Fetch direct parfois bloqué côté Claude consumer — depuis GitHub Actions, tester en direct.'),
 ('https://fr.wordpress.org/plugins/', 'WordPress.org plugins (FR)', 'installs actives, avis nommant les manques', 'seed (runs août)', 'active', 4, 'PRODUCTIF.'),
 ('https://addons.prestashop.com', 'PrestaShop Addons', 'avis, prix — écosystème FRANÇAIS', 'seed (analyse 2026-08-20)', 'candidate', null, 'Jamais foré : e-commerce FR au cœur du pattern gagnant.'),
 ('https://woocommerce.com/products/', 'WooCommerce Extensions', 'avis, prix', 'seed', 'candidate', null, null),
 ('https://www.indiehackers.com', 'Indie Hackers (interviews MRR publié)', 'MRR sourcé', 'seed (runs août)', 'active', 4, 'Meilleure preuve de traction chiffrée quand MRR publié. Accès parfois bloqué — tester en direct depuis le runner.'),
 ('https://www.legifrance.gouv.fr', 'Légifrance', 'textes, échéances réglementaires', 'seed (runs août)', 'active', 4, 'Prouve trou_fr, jamais canal.'),
 ('https://www.economie.gouv.fr/dgccrf', 'DGCCRF', 'obligations pro, calendriers', 'seed', 'active', 3, null),
 ('https://eur-lex.europa.eu', 'EUR-Lex', 'règlements UE, dates d''entrée en vigueur', 'seed', 'active', 3, null),
 ('https://www.appvizer.fr', 'Appvizer (comparateur logiciels FR)', 'paysage concurrentiel FR par métier', 'seed (analyse)', 'candidate', null, 'Pour tuer/prouver le trou FR vite.'),
 ('https://hunted.space', 'hunted.space (miroir PH)', 'lancements datés', 'seed (runs août)', 'active', 2, 'Uniquement pour dédup / pointer un produit précis.'),
 ('https://shopscan.app/shopify-apps/recently-launched', 'shopscan.app', 'nouveautés Shopify (agrégateur)', 'seed (runs août)', 'active', 2, 'FRAÎCHEUR PEU FIABLE (ré-indexations datées « il y a 7h »). Toujours croiser.'),
 ('https://acquire.com', 'Acquire.com (rachats micro-SaaS)', 'MRR et prix de vente publiés', 'seed (analyse)', 'candidate', null, 'WTP prouvée par les prix payés.'),
 ('https://microns.io', 'Microns (micro-acquisitions)', 'MRR/prix', 'seed (analyse)', 'candidate', null, null),
 ('https://community.shopify.com', 'Shopify Community (forums support)', 'plaintes et manques fonctionnels publics, horodatés', 'seed (2026-08-21)', 'candidate', null, 'Mine de douleur e-commerce. Prouve la douleur et le vocabulaire, jamais WTP/canal.'),
 ('https://www.reddit.com', 'Reddit (subs métiers / SaaS / FR)', 'douleur, workarounds, vocabulaire métier', 'seed (2026-08-21)', 'candidate', null, 'Accès à TESTER depuis le runner (403 documenté côté Claude consumer en août) : direct → old.reddit.com → flux .rss/.json → Firecrawl. Mur persistant → enterrer avec raison, retester après 14 j.'),
 ('https://raw.githubusercontent.com/sindresorhus/awesome/main/readme.md', 'Awesome (index des listes curées)', 'source de sources : annuaires d''outils par sujet', 'seed (2026-08-20)', 'candidate', null, 'Lisible en raw, zéro anti-bot. Prospecteur : chercher la liste awesome du vertical foré. Ne prouve jamais traction ni WTP — vague 0 uniquement.'),
 ('https://github.com/awesome-selfhosted/awesome-selfhosted-data', 'awesome-selfhosted-data (YAML machine-readable)', 'catégories SaaS à demande prouvée + substituts open source', 'seed (2026-08-20)', 'candidate', null, 'Double usage. Contre-avocat : un open source auto-hébergeable couvrant le JTBD = attaque directe de la jambe WTP. Prospecteur : cartographie des catégories qui valent qu''on les self-host.')
on conflict (url) do nothing;

-- RLS : ces tables du schéma public seraient sinon lisibles/modifiables
-- via PostgREST avec la clé anon (les agents passent par psql, non concernés).
alter table sources        enable row level security;
alter table carte_naf      enable row level security;
alter table reserves       enable row level security;
alter table doctrine       enable row level security;
alter table verdicts       enable row level security;

-- Fin. Vérifications rapides :
--   select statut, count(*) from sources group by 1;
--   select count(*) from doctrine where statut='actif';
--   select count(*) from reserves;
