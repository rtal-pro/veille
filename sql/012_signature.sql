-- ============================================================
-- Migration 012 — LA SIGNATURE STRUCTURELLE : donner au système une mémoire
-- comparable, et non plus un journal de singletons.
-- Décision humaine du 2026-09-15, prise sur mesure.
--
-- ------------------------------------------------------------
-- CE QUI L'A FORCÉE — mesure du 2026-09-14 sur la base entière :
--   155 dossiers · 153 secteurs distincts · 1,01 dossier par secteur ·
--   ZÉRO dossier partageant son secteur avec deux autres.
-- Le seul champ de classement de la base a une cardinalité de un. Il est donc
-- structurellement impossible de demander « parmi les dossiers qui
-- ressemblaient à celui-ci, combien ont survécu ? » — aucun dossier ne
-- ressemble jamais à un autre sous le seul classement disponible. 155 lignes,
-- zéro classe : le système ne peut rien apprendre de ses propres morts.
--
-- Pourtant les motifs existent, et les agents les écrivent EN PROSE, faute
-- d'un endroit où les mettre :
--   · « même mécanisme que les 27 dossiers précédents »       (contre-avocat, CompanyCam, 12/09)
--   · « rupture avec le mécanisme des 16 dossiers précédents » (instructeur, MarketMan, 09/09)
--   · « quatrième forme du même tueur depuis le 06/09 »        (instructeur, WildApricot, 09/09)
--   · « test délibéré de mon hypothèse du 09/09 : une catégorie à plancher
--      HAUT est la seule qui ait résisté »  (instructeur, Statii, 11/09 — hypothèse
--      formée, testée deux jours plus tard, réfutée par son propre auteur)
-- Le système sait former une hypothèse et la falsifier. Rien ne le capture.
--
-- Le secteur est une ressemblance de SURFACE. Les deux survivants de la base
-- n'ont rien de sectoriel en commun — bénévolat associatif, intake juridique —
-- et sont structurellement IDENTIQUES : le leader refuse le petit segment,
-- aucun challenger bon marché n'occupe le trou ouvert, tous les modernes se
-- vendent sur devis. C'est cette configuration-là qu'il faut pouvoir compter.
--
-- ------------------------------------------------------------
-- POURQUOI LA CLASSE DE RÉFÉRENCE EST HIÉRARCHIQUE (et pas à quatre axes d'un
-- coup). La littérature sur le reference class forecasting est explicite : une
-- classe trop ÉTROITE produit une estimation BIAISÉE, pas plus précise — « le
-- risque d'une classe sous-dimensionnée et peu informative ». Quatre axes
-- croisés font 384 cases pour 155 dossiers : la quasi-totalité serait à n=0 ou
-- n=1, et un taux de survie sur un dossier n'est pas un taux, c'est une
-- anecdote déguisée en chiffre.
-- D'où `v_taux_de_base`, qui expose TROIS niveaux de finesse et le nombre de
-- dossiers jugés à chacun. La consigne d'usage est : descendre au niveau le
-- plus fin dont `juges >= 10`, et pas plus bas.
-- Règle d'usage tirée de la même littérature, et qui vaut plus que la colonne :
-- PARTIR DE LA MÉDIANE DE LA CLASSE PUIS AJUSTER — jamais partir du récit du
-- dossier et ajuster vers le taux de base.
--
-- ------------------------------------------------------------
-- VOCABULAIRE CONTRÔLÉ (quatre axes). Un agent qui invente une valeur hors de
-- cette liste casse le comptage : c'est l'unique intérêt d'un vocabulaire fermé.
--   plancher       : occupe_gratuit | occupe_bon_marche | vide | inconnu
--                    (axe PRIMAIRE — c'est lui qui tue 48 % des dossiers)
--   forme_trou     : refus_publie | douleur_ancienne | integration_manquante
--                    | job_neuf | segment_orphelin | aucun
--   vente_modernes : self_serve | devis | mixte | inconnu
--   palier         : bas | moyen | haut | inconnu   (bas <60$, moyen 60-149$, haut >=150$)
--
-- QUI ÉCRIT QUOI : le Kiosque pose `plancher` et `palier` à la récolte (il les
-- relève déjà dans `concurrents`) ; l'Instructeur complète `forme_trou` et
-- `vente_modernes` à l'instruction. Le Fossoyeur rattrape l'historique.
--
-- Idempotente : rejouable sans effet de bord (tests/test_migrations.sh rejoue
-- toutes les migrations DEUX FOIS et compare l'état de `doctrine`).
-- ============================================================

alter table prospection_clones add column if not exists signature jsonb;

comment on column prospection_clones.signature is
  'Signature structurelle à vocabulaire contrôlé (migration 012). Quatre clés : '
  'plancher (primaire), forme_trou, vente_modernes, palier. Kiosque pose '
  'plancher+palier à la récolte, Instructeur complète forme_trou+vente_modernes. '
  'Sert la classe de référence hiérarchique (v_taux_de_base) et la carte des '
  'angles morts (v_couverture_signature). Le secteur reste une ressemblance de '
  'surface : 153 valeurs distinctes pour 155 dossiers au 2026-09-14.';

create index if not exists idx_pc_signature on prospection_clones using gin (signature);

-- ------------------------------------------------------------
-- LA CLASSE DE RÉFÉRENCE, À TROIS NIVEAUX DE FINESSE.
-- On ne compte les survivants que sur les dossiers REFERMÉS : un lead encore au
-- vivier n'a pas d'issue, et l'inclure écraserait le taux vers le bas au fil de
-- la journée. `encore_au_vivier` reste affiché pour que ça se voie.
-- ------------------------------------------------------------
create or replace view v_taux_de_base as
with base as (
  select
    coalesce(signature->>'plancher',       '(non signé)') as plancher,
    coalesce(signature->>'forme_trou',     '(non signé)') as forme_trou,
    coalesce(signature->>'vente_modernes', '(non signé)') as vente_modernes,
    coalesce(signature->>'palier',         '(non signé)') as palier,
    statut_pipeline, date_run
  from prospection_clones
),
compte as (
  select 1 as niveau, plancher, '*' as forme_trou, '*' as vente_modernes, '*' as palier,
         statut_pipeline, date_run from base
  union all
  select 2, plancher, forme_trou, '*', '*', statut_pipeline, date_run from base
  union all
  select 3, plancher, forme_trou, vente_modernes, palier, statut_pipeline, date_run from base
)
select niveau, plancher, forme_trou, vente_modernes, palier,
       count(*) filter (where statut_pipeline in ('ecarte','tue','survivant')) as juges,
       count(*) filter (where statut_pipeline = 'survivant')                   as survivants,
       round(100.0 * count(*) filter (where statut_pipeline = 'survivant')
             / nullif(count(*) filter (where statut_pipeline in ('ecarte','tue','survivant')), 0), 1)
                                                                              as taux_survie_pct,
       count(*) filter (where statut_pipeline = 'lead')                       as encore_au_vivier,
       max(date_run)                                                          as dernier_vu
from compte
group by 1, 2, 3, 4, 5
order by niveau, juges desc;

comment on view v_taux_de_base is
  'Classe de référence HIÉRARCHIQUE. niveau 1 = plancher seul (classe large), '
  'niveau 2 = plancher+forme_trou, niveau 3 = les quatre axes (classe étroite). '
  'À lire AVANT d''instruire : descendre au niveau le plus fin dont juges >= 10, '
  'et pas plus bas — en dessous, le taux est une anecdote. Partir de la médiane '
  'de la classe puis ajuster, jamais l''inverse.';

-- ------------------------------------------------------------
-- LA CARTE DES ANGLES MORTS — les 384 configurations du vocabulaire, et ce que
-- la base en occupe. `juges = 0` = un endroit où le système n'a JAMAIS regardé,
-- que personne n'a décidé d'éviter. Ce n'est PAS une liste d'idées, et ce n'est
-- surtout PAS une source de taux de base (n y est nul par construction) : ça se
-- lit comme `carte_produits` se lit pour les terrains.
-- ------------------------------------------------------------
create or replace view v_couverture_signature as
with vocab as (
  select p.v as plancher, f.v as forme_trou, m.v as vente_modernes, t.v as palier
  from      (values ('occupe_gratuit'), ('occupe_bon_marche'), ('vide'), ('inconnu')) p(v)
  cross join (values ('refus_publie'), ('douleur_ancienne'), ('integration_manquante'),
                     ('job_neuf'), ('segment_orphelin'), ('aucun'))                   f(v)
  cross join (values ('self_serve'), ('devis'), ('mixte'), ('inconnu'))               m(v)
  cross join (values ('bas'), ('moyen'), ('haut'), ('inconnu'))                       t(v)
),
observe as (
  select signature->>'plancher' p, signature->>'forme_trou' f,
         signature->>'vente_modernes' m, signature->>'palier' t,
         count(*) filter (where statut_pipeline in ('ecarte','tue','survivant')) juges,
         count(*) filter (where statut_pipeline = 'survivant')                  survivants
  from prospection_clones where signature is not null
  group by 1, 2, 3, 4
)
select v.plancher, v.forme_trou, v.vente_modernes, v.palier,
       coalesce(o.juges, 0) as juges, coalesce(o.survivants, 0) as survivants
from vocab v
left join observe o
  on o.p = v.plancher and o.f = v.forme_trou
 and o.m = v.vente_modernes and o.t = v.palier
order by coalesce(o.survivants, 0) desc, coalesce(o.juges, 0) asc;

comment on view v_couverture_signature is
  'Les 384 configurations du vocabulaire contrôlé, avec ce que la base en a jugé. '
  'juges = 0 : angle mort jamais exploré. Lue chaque dimanche par le Fossoyeur. '
  'Ne JAMAIS en tirer un taux de survie : les cases y sont vides par construction.';

-- ------------------------------------------------------------
-- Accès agent_veille — gabarit de 006 : une vue doit être grantée
-- explicitement, le grant sur la table ne suffit pas. La colonne `signature`
-- est couverte par le grant de 006 sur prospection_clones.
-- ------------------------------------------------------------
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'agent_veille') then
    grant select on v_taux_de_base, v_couverture_signature to agent_veille;
  end if;
end $$;

-- ------------------------------------------------------------
-- Doctrine. NE commence PAS par « Product Hunt » : tests/test_migrations.sh
-- compte les règles actives commençant ainsi et en attend exactement une.
-- `on conflict do nothing` + unicité sur `regle` : rejouable sans doublon.
-- ------------------------------------------------------------
insert into doctrine (regle, type, origine) values
 ('LA CLASSE DE RÉFÉRENCE AVANT L''INSTRUCTION. Tout dossier porte une signature structurelle à vocabulaire FERMÉ (plancher, forme_trou, vente_modernes, palier — migration 012), et l''Instructeur lit `v_taux_de_base` AVANT d''instruire : il descend au niveau le plus fin dont `juges >= 10`, part de la médiane de cette classe, PUIS ajuste avec les particularités du dossier — jamais l''inverse. Une signature dont le taux de survie est nul sur un effectif suffisant justifie un tri de deux minutes, pas une instruction de quinze. Deux gardes. (1) Ne jamais descendre sous 10 dossiers jugés : une classe sous-dimensionnée produit une estimation BIAISÉE, pas précise, et un taux calculé sur un dossier est une anecdote déguisée en chiffre. (2) Ne jamais tirer un taux de `v_couverture_signature`, dont les cases sont vides par construction. Pourquoi cette règle existe : mesure du 2026-09-14, la base comptait 155 dossiers pour 153 secteurs distincts — le seul champ de classement avait une cardinalité de un, aucun dossier ne ressemblait jamais à un autre, et le système ne pouvait donc rien apprendre de ses propres morts. Le secteur est une ressemblance de surface ; les deux seuls survivants (bénévolat associatif, intake juridique) n''ont aucun secteur commun et une structure identique.',
  'garde_fou', '2026-09-15 signature structurelle')
on conflict do nothing;

-- ------------------------------------------------------------
-- Vérifications (à lancer à la main après application) :
--   select count(*) from information_schema.columns
--     where table_name='prospection_clones' and column_name='signature';      -- 1
--   select count(*) from v_couverture_signature;                               -- 384
--   select distinct niveau from v_taux_de_base order by 1;                     -- 1,2,3
--   select count(*) from prospection_clones where signature is not null;       -- 0 avant rattrapage
--   select count(*) from doctrine where statut='actif' and regle like 'Product Hunt%';  -- 1
-- ------------------------------------------------------------
