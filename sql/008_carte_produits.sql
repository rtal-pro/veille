-- ============================================================
-- Migration 008 — Carte des terrains PRODUITS (le pendant de carte_naf)
-- À exécuter après 007. Idempotente.
--
-- POURQUOI. Mesure du 2026-08-31 sur la base réelle : le système sait toujours
-- où il en est de la chasse au MÉTIER (carte_naf : 732 sous-classes, 91
-- explorées, 87 stériles, 554 vierges — donc jamais deux fois le même secteur),
-- mais il n'a AUCUNE carte pour la chasse au PRODUIT. Résultat sur 555 sources
-- en base : producthunt 0, appsumo 0, g2 0, hackernews 0, indiehackers 1,
-- capterra 10, et 292 sources françaises. Le catalogue mondial des SaaS qui
-- marchent est absent du système.
--
-- Conséquence observée : un agent n'est méthodique que sur un terrain
-- ÉNUMÉRABLE. N'ayant qu'une seule carte sous la main, le Kiosque y retourne
-- indéfiniment — d'où le pattern « métier nommable + logiciel » testé plus de
-- 120 fois selon ses propres journaux, un rendement tombé à 0/8 sur les codes
-- NAF tirés au hasard le 30/08, et 4 cycles consécutifs à zéro lead ce jour-là.
--
-- Cette table donne des cases à cocher à la chasse au clone, exactement comme
-- carte_naf en donne à la chasse au métier.
--
-- AMORÇAGE, ET CE QU'ON N'INVENTE PAS. Seules les tranches purement
-- CALENDAIRES sont pré-remplies ici : une semaine ISO est un fait, pas une
-- supposition. Les catégories réelles d'AppSumo, Capterra ou G2 ne sont PAS
-- récitées de mémoire — même discipline que carte_naf, dont le Prospecteur
-- doit lire la nomenclature INSEE plutôt que la réciter. Chaque terrain non
-- calendaire reçoit donc une tranche d'amorçage qui demande d'aller LIRE la
-- liste des catégories sur place, puis de créer une tranche par catégorie.
-- ============================================================

create table if not exists carte_produits (
  id bigint generated always as identity primary key,
  terrain text not null,                     -- producthunt | appsumo | capterra | g2 | indiehackers | acquire
  tranche text not null,                     -- LA case à cocher : 'semaine 2026-W35', 'categorie: facturation'
  url text,                                  -- l'URL exacte à ouvrir (remplie à la première exploration)
  statut text not null default 'vierge'
    check (statut in ('vierge','exploree','sterile')),
  date_exploration date,
  leads_trouves integer not null default 0,  -- combien d'idées cette tranche a réellement données
  notes text,                                -- ce qu'on y a vu ; pourquoi stérile le cas échéant
  created_at timestamptz not null default now(),
  unique (terrain, tranche)
);

create index if not exists idx_carte_produits_a_faire
  on carte_produits (terrain, statut) where statut = 'vierge';

alter table carte_produits enable row level security;

-- CE QUE CETTE CARTE NE COUVRE PAS, ET POURQUOI. Product Hunt et Hacker News
-- en sont volontairement absents : la doctrine active (001) mesure que leur flux
-- généraliste est stérile pour du vertical clonable (« ≈ 95 % de bruit, documenté
-- 4 runs sur 5 ») tout en gardant leur seul usage rentable — un sas de 5 min pour
-- détecter les convergences. Cette règle-là n'est pas révisée ici : elle porte sur
-- un flux de LANCEMENTS, quand cette carte porte sur des catalogues de produits
-- qui ont DÉJÀ des clients payants. Ce sont deux terrains différents, pas deux
-- avis sur le même.

-- Chaque terrain reçoit une tranche d'amorçage qui impose la LECTURE de la liste
-- réelle des catégories avant de créer les cases à cocher.
insert into carte_produits (terrain, tranche, notes) values
 ('appsumo',      '_cartographier les categories',
  'Premier passage : ouvrir le site, relever la liste RÉELLE des catégories/collections, créer une tranche par catégorie, puis passer CETTE tranche en exploree. Ne jamais réciter les catégories de mémoire.'),
 ('capterra',     '_cartographier les categories',
  'Idem. Capterra FR expose des catégories de logiciels par usage ET par métier : la version FR sert aussi à mesurer le trou français d''une catégorie US.'),
 ('g2',           '_cartographier les categories',
  'Idem. G2 porte les avis et les grilles de prix : c''est un lieu de preuve de TRACTION (des clients qui paient), pas seulement un annuaire.'),
 ('indiehackers', '_cartographier les gisements',
  'Idem : relever les sections/tags où des fondateurs publient des revenus réels. Ce sont des preuves de WTP datées et citables.'),
 ('acquire',      '_cartographier les gisements',
  'Marketplaces de rachat de SaaS : un produit mis en vente avec son MRR affiché est une preuve de traction chiffrée, et son acquéreur potentiel en France n''existe souvent pas.')
on conflict (terrain, tranche) do nothing;

-- Où en est la chasse au produit ? La question qu'on ne pouvait pas poser.
create or replace view v_carte_produits with (security_invoker = true) as
select terrain,
       count(*)                                   as tranches,
       count(*) filter (where statut = 'vierge')  as vierges,
       count(*) filter (where statut = 'exploree')as explorees,
       count(*) filter (where statut = 'sterile') as steriles,
       coalesce(sum(leads_trouves), 0)            as leads_cumules,
       max(date_exploration)                      as derniere_exploration
from carte_produits
group by terrain
order by vierges desc;

do $$ begin
  if exists (select 1 from pg_roles where rolname = 'agent_veille') then
    grant select, insert, update on carte_produits to agent_veille;
    grant select on v_carte_produits to agent_veille;
    grant usage, select on all sequences in schema public to agent_veille;
    drop policy if exists agent_veille_all on carte_produits;
    create policy agent_veille_all on carte_produits
      for all to agent_veille using (true) with check (true);
  end if;
end $$;

do $$ begin
  revoke all on v_carte_produits from anon, authenticated;
exception when undefined_object then null; end $$;

-- Doctrine : la stratégie de chasse devient une règle, pas une intention.
insert into doctrine (regle, type, origine) values
 ('L''ordre de preuve d''un clone est TRACTION D''ABORD, TROU ENSUITE. Un lead part d''un produit dont on peut montrer par URL que des gens le paient déjà ailleurs (avis, prix affiché, MRR publié, classement) ; ensuite seulement on vérifie qu''il manque en France. Mesure du 2026-08-31 sur les 18 idées produites : 18/18 portaient une preuve du trou FR, mais 1/18 seulement l''URL d''une preuve de traction. Chercher un trou sans preuve de demande, c''est chercher un endroit où personne ne vend de pain en espérant que des gens y ont faim — les journaux du Kiosque rapportent 3 à 6 concurrents déjà nommés à chaque tentative.', 'garde_fou', '2026-08-31 divorce schéma/prompts'),
 ('La chasse au produit se fait sur carte_produits, tranche par tranche, comme la chasse au métier se fait sur carte_naf. Prendre une tranche vierge, la dépouiller, la passer exploree ou sterile avec ses notes. Un terrain sans carte est un terrain qu''on relaboure : c''est ce qui a produit plus de 120 tests du même angle « métier nommable + logiciel ».', 'garde_fou', '2026-08-31 carte des produits'),
 ('Les catalogues de produits ÉTABLIS — AppSumo, G2, Capterra, Indie Hackers, marketplaces de rachat — sont les gisements PRIMAIRES de la chasse au clone, parce qu''on y lit une preuve de traction (avis, prix affiché, revenus publiés, MRR en vente) avant même de parler de la France. À ne pas confondre avec le sas Product Hunt / Hacker News, qui reste plafonné à 5 min par la doctrine existante : celui-là est un flux de lancements sans clients, celui-ci un catalogue de produits qui en ont. Mesure du 2026-08-31 : sur 555 sources en base, appsumo 0, g2 0, indiehackers 1, capterra 10 — le gisement primaire n''était tout simplement pas branché.', 'heuristique', '2026-08-31 carte des produits')
on conflict do nothing;

-- Vérification : select * from v_carte_produits;
