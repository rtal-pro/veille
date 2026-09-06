-- ============================================================
-- Migration 011 — PIVOT : du micro-SaaS FR vertical au SaaS horizontal
-- anglophone. Décision humaine du 2026-09-06, prise sur mesure.
--
-- Ce qui a forcé le pivot :
--   · 43 dossiers instruits depuis l'origine, 1 seul GO ;
--   · 28/31 morts à la jambe « trou FR » avant le déblocage de
--     l'approvisionnement, puis 12/14 au PREMIER run correctement alimenté
--     (leads à traction prouvée par URL : Booqable, Sortly, RepairShopr,
--     Time To Pet, Turno, TaxDome, Buildium, dotloop, GorillaDesk…).
--     Le second échantillon est le premier correctement formé du système, et
--     il réfute l'hypothèse centrale : sur des jobs verticaux nommables, la
--     France est déjà servie.
--   · Le produit de référence choisi par le créateur, NudgeForMe (agent IA de
--     relance d'emails, lancé sur Product Hunt le 2026-08-01, Pro à 12 $/mois),
--     aurait été tué en une requête par cette doctrine : horizontal, non
--     français, des dizaines de concurrents, et issu du gisement que la
--     doctrine classait « 95 % de bruit ».
--
-- Les trois arbitrages tranchés :
--   1. La jambe « trou FR » est remplacée par l'ANGLE DÉFENDABLE. Sur un
--      marché horizontal, un concurrent existe toujours : sa présence cesse
--      d'être un tueur, son absence cesse d'être une preuve.
--   2. Le marché cible devient ANGLOPHONE MONDIAL. Toute la hiérarchie
--      géographique des sources perd son objet.
--   3. Product Hunt / Hacker News passent de sas plafonné à GISEMENT PRIMAIRE.
--
-- Idempotence : mêmes trois contraintes qu'en 010 (index unique md5(regle),
-- jamais de réécriture en place d'une règle semée par une migration, ancrage
-- md5 EXACT relevé en prod le 2026-09-06). Les renommages de colonnes et la
-- réécriture de clé JSON sont gardés par des tests d'existence.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Schéma : deux noms de colonnes qui mentiraient après le pivot.
--    `preuve_trou_fr` ne prouve plus un trou français, `concurrents_fr` n'est
--    plus restreint à la France. Un champ dont le nom ment est exactement le
--    genre de dette qui fait diverger le code et la doctrine.
--    Gardés des deux côtés (source présente ET cible absente) pour rester
--    rejouables : 000_legacy recrée la table aux anciens noms sur une base
--    fraîche, cette migration la corrige, et la passe suivante ne fait rien.
-- ------------------------------------------------------------
do $$ begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='prospection_clones'
                and column_name='preuve_trou_fr')
 and not exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='prospection_clones'
                and column_name='preuve_angle')
  then alter table prospection_clones rename column preuve_trou_fr to preuve_angle;
  end if;
end $$;

do $$ begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='prospection_clones'
                and column_name='concurrents_fr')
 and not exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='prospection_clones'
                and column_name='concurrents')
  then alter table prospection_clones rename column concurrents_fr to concurrents;
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. statut_jambes : la clé `trou_fr` devient `angle`, historique compris.
--    Les dossiers passés gardent ainsi un sens lisible (leur jambe 1 a bien
--    été instruite, sous l'ancien critère) au lieu de porter une clé que plus
--    aucun prompt ne connaît. Idempotent : après passage, plus aucune ligne ne
--    porte 'trou_fr', donc le WHERE ne rend plus rien.
-- ------------------------------------------------------------
update prospection_clones
   set statut_jambes = (statut_jambes - 'trou_fr')
                       || jsonb_build_object('angle', statut_jambes -> 'trou_fr')
 where statut_jambes ? 'trou_fr';

-- ------------------------------------------------------------
-- 3. Doctrine : ce que le pivot rend caduc.
--    Six règles perdent leur objet d'un coup — elles disent toutes, sous des
--    formes différentes, « comment juger un trou sur le marché français ».
--    Ancrage md5 relevé en prod le 2026-09-06.
-- ------------------------------------------------------------
update doctrine set statut='obsolete',
  origine = origine || ' — caduque au pivot marché anglophone (2026-09-06)'
 where statut='actif' and md5(regle) = '892063eb9d73a5db3244f686dbea1aac';  -- #3  hiérarchie géographique conformité UE

update doctrine set statut='obsolete',
  origine = origine || ' — caduque au pivot marché anglophone (2026-09-06)'
 where statut='actif' and md5(regle) = '461d7791e3ba814d0a3a8bf01c8dc2c7';  -- #4  la France est-elle déjà en avance

update doctrine set statut='obsolete',
  origine = origine || ' — caduque au pivot marché anglophone (2026-09-06)'
 where statut='actif' and md5(regle) = 'ad0ea45ba98764f7f173bb8f04bc4dc3';  -- #5  source nordique = mécanisme, pas transposabilité

update doctrine set statut='obsolete',
  origine = origine || ' — caduque au pivot marché anglophone (2026-09-06)'
 where statut='actif' and md5(regle) = '63bd881fb0c3c6020ff93bdf8b1ff64f';  -- #8  Shopify absorbe la conformité d'affichage FR

update doctrine set statut='obsolete',
  origine = origine || ' — caduque au pivot marché anglophone (2026-09-06)'
 where statut='actif' and md5(regle) = 'aaef69f94eb7a9a7159f5716cc09b499';  -- #410 guichet public gratuit français

update doctrine set statut='obsolete',
  origine = origine || ' — caduque au pivot marché anglophone (2026-09-06)'
 where statut='actif' and md5(regle) = '97cf402e951fa8b72aa3d15531eec007';  -- #411 absorption d'une obligation réglementaire

-- Trois règles restent valides dans leur intention mais nomment l'ancien
-- critère : réécrites (obsolete + insert, jamais en place).
update doctrine set statut='obsolete',
  origine = origine || ' — réécrite au pivot : la jambe 1 devient l''angle défendable (2026-09-06)'
 where statut='actif' and md5(regle) = '2d74aefe1ff10a8a6c95159b8e52858c';  -- ordre de preuve

update doctrine set statut='obsolete',
  origine = origine || ' — réécrite au pivot : PH/HN passent en gisement primaire (2026-09-06)'
 where statut='actif' and md5(regle) = '3f1612a375f6fbf74e268f9b9740ab34';  -- sas de nouveauté

update doctrine set statut='obsolete',
  origine = origine || ' — réécrite au pivot : PH/HN rejoignent les gisements primaires (2026-09-06)'
 where statut='actif' and md5(regle) = '1780acbb3b94174ece05342648d53ef0';  -- catalogues établis

-- ------------------------------------------------------------
-- 4. La doctrine du pivot.
--    Bilan du plafond (règle #16, 25 actives max) : 25 - 9 + 5 = 21.
-- ------------------------------------------------------------
insert into doctrine (regle, origine, type, derniere_revision) values

 ('JAMBE 1 — L''ANGLE DÉFENDABLE remplace le « trou FR », retiré le 2026-09-06. Sur un marché horizontal mondial un concurrent existe TOUJOURS : sa présence n''est plus un tueur, son absence n''est plus une preuve. Le tueur devient l''absence de coin défendable. Un dossier ne passe la jambe 1 que si tu nommes UN de ces quatre coins ET que tu le PROUVES par une URL LUE : (1) INTÉGRATION MANQUANTE — la page d''intégrations du leader ne couvre pas une plateforme ou un format que la cible utilise (URL où l''absence se lit + URL prouvant l''usage par la cible) ; (2) SEGMENT DÉLAISSÉ — le palier d''entrée du leader est hors de portée de la cible, ou sa page clients montre qu''il vise plus gros (URL du pricing ou des références) ; (3) DOULEUR NON RÉSOLUE — plaintes publiques récurrentes et DATÉES sur les produits existants (avis 1-2 étoiles, issues GitHub, threads de support) ; (4) JOB NEUF — tous les concurrents identifiés ont moins de 18 mois (URL de leurs dates de lancement). Aucun coin prouvé par URL → angle RÉFUTÉ → écarté.',
  'pivot 2026-09-06 — décision humaine après 43 dossiers et 1 GO', 'garde_fou', '2026-09-06'),

 ('GARDE DU CRITÈRE D''ANGLE : un coin ARGUMENTÉ mais non lu reste HYPOTHÈSE, jamais PROUVÉ. Cette garde existe parce que le nouveau critère est plus SOUPLE que celui qu''il remplace : « il manque un coin défendable » se démontre moins mécaniquement que « un concurrent français existe ». Sans elle, la jambe 1 deviendrait un tampon GO automatique et le système se remettrait à fabriquer — la faute maximale. Même standard que partout ailleurs : aucun verdict sans URL lue, dans un sens comme dans l''autre.',
  'pivot 2026-09-06 — contrepoids au relâchement du critère', 'garde_fou', '2026-09-06'),

 ('MARCHÉ CIBLE : ANGLOPHONE MONDIAL. Produit en anglais, clients partout, distribution Product Hunt / SEO / communautés. La contrainte « marché français » est retirée le 2026-09-06 : elle a produit 28 morts sur 31 à la jambe trou_fr, puis 12 sur 14 au premier run correctement approvisionné — le premier échantillon proprement formé du système, et il réfute son hypothèse centrale. Deux corollaires opérationnels : ne PLUS écarter une idée parce qu''un acteur français la sert déjà ; ne plus partir d''un métier nommable (nomenclature NAF) pour trouver le gibier, mais d''un JOB horizontal que beaucoup de métiers partagent — modèle de référence : NudgeForMe, relance des emails restés sans réponse, utile à tout métier qui a une boîte mail.',
  'pivot 2026-09-06 — décision humaine', 'garde_fou', '2026-09-06'),

 ('ORDRE DE PREUVE UNIQUE — TRACTION D''ABORD, ANGLE ENSUITE. Un lead n''entre dans prospection_clones QUE s''il porte déjà l''URL d''une preuve que des gens PAIENT le produit ailleurs (avis nombreux et datés, prix public affiché, MRR publié, revenus publiés) : c''est la jambe 0, le ticket d''entrée du vivier, posée par le récolteur avec saas_source + preuve_traction_us + source_traction_us + traction:PROUVÉ. L''Instructeur ne ré-instruit pas la traction : il ouvre l''URL, vérifie qu''elle dit ce qu''elle prétend, puis instruit angle → canal → WTP. Mesure 2026-09-06 : 28/31 des dossiers historiques portaient une preuve du trou français, 4/31 seulement une preuve de traction. Chercher un trou sans preuve de demande, c''est chercher un endroit où personne ne vend de pain en espérant que des gens y ont faim.',
  'seed 008, réécrite au pivot du 2026-09-06', 'garde_fou', '2026-09-06'),

 ('GISEMENTS PRIMAIRES : Product Hunt / Hacker News (lancements de 3 à 12 MOIS), AppSumo, G2, Capterra, Indie Hackers, marketplaces de rachat. Le plafond de 5 min sur PH/HN est retiré le 2026-09-06 : c''est là qu''apparaissent les jobs que l''IA vient de rendre faisables, et c''est de là que vient NudgeForMe (lancé le 2026-08-01, Pro à 12 $/mois), le modèle de référence du système. Deux gardes remplacent le plafond de temps, parce que le volume est énorme et qu''un lancement du JOUR ne porte AUCUNE preuve de traction : (1) ne récolter que des lancements de 3 à 12 mois, dont on peut LIRE ce qu''ils sont devenus — avis accumulés, prix, clients : la jambe 0 reste intacte ; (2) privilégier les CONVERGENCES (2+ lancements sur le même job la même semaine = douleur réelle). Le digest de lecture de `nouveautes` reste un livrable distinct : un produit qui y figure n''est pas un candidat.',
  'seeds 008/009, fusionnées et réécrites au pivot du 2026-09-06', 'garde_fou', '2026-09-06')

on conflict do nothing;

-- ------------------------------------------------------------
-- Vérifications (à lancer à la main après application) :
--   select count(*) from doctrine where statut='actif';                             -- attendu : 21
--   select count(*) from prospection_clones where statut_jambes ? 'trou_fr';         -- 0
--   select count(*) from information_schema.columns
--     where table_name='prospection_clones' and column_name in ('preuve_angle','concurrents');  -- 2
--   select count(*) from doctrine where statut='actif' and regle like '%trou FR%';   -- 0 hors mention historique
-- ------------------------------------------------------------
