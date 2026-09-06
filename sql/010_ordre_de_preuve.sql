-- ============================================================
-- Migration 010 — Cohérence de la doctrine : un seul ordre de preuve.
--
-- Diagnostic du 2026-09-06 (12 jours d'exploitation, 31 dossiers) :
--   · 1 seul GO dans toute la base, 11 jours rouges sur 12 ;
--   · 28/31 dossiers morts à la jambe trou_fr ;
--   · 28/31 portaient une preuve du trou FR, 4/31 seulement une URL de traction ;
--   · le Contre-avocat a tourné 12 runs consécutifs avec une file VIDE.
--
-- Cause : DEUX règles actives se contredisaient frontalement — #1 « trou FR
-- d'abord » (heuristique, seed 001) contre #512 « traction d'abord, trou
-- ensuite » (garde_fou, 2026-08-31). Deux règles contradictoires, ce n'est pas
-- une nuance : c'est un tirage au sort à chaque run, et en pratique c'est
-- toujours celle écrite dans le prompt de rôle qui gagnait. Mesure : 6 jours
-- après l'entrée en vigueur du garde-fou #512, le ratio n'avait pas bougé
-- (10/13 preuve de trou, 3/13 preuve de traction).
--
-- Cette migration tranche : TRACTION D'ABORD est la règle unique.
--
-- Idempotence — trois contraintes du dépôt, respectées ici :
--   1. `idx_doctrine_unique` sur md5(regle) : tout INSERT porte
--      `on conflict do nothing`.
--   2. Une règle SEMÉE par 001 ne se réécrit JAMAIS en place : 001 rejoue à
--      chaque passe et ré-insérerait l'ancien texte (son md5 aurait disparu).
--      Le motif maison est donc : passer l'ancienne `obsolete` (ancrage md5
--      EXACT, jamais un LIKE de préfixe) + insérer la corrigée.
--   3. Le motif vaut pour TOUTE règle semée par une migration, pas seulement
--      celles de 001 : #512 vient de 008 et #699 de 009. C'est précisément
--      l'erreur qu'a attrapée tests/test_migrations.sh à la première rédaction
--      de ce fichier — #512 réécrite en place, 008 ré-insérant l'original au
--      replay, puis collision md5 sur la réécriture. Le banc de test exige
--      count+sum(id) des règles actives identiques entre les deux passes.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Les cinq règles remplacées passent `obsolete`.
--    Ancrage md5 EXACT (jamais un LIKE de préfixe), et md5 vérifiés identiques
--    entre le seed du dépôt et la prod le 2026-09-06. Garder la ligne obsolete
--    en base n'est pas cosmétique : c'est elle qui fait échouer le `on conflict
--    do nothing` du seed au replay suivant, donc qui empêche l'ancienne règle
--    de ressusciter.
-- ------------------------------------------------------------
update doctrine set statut = 'obsolete',
  origine = origine || ' — absorbée par #512 (ordre de preuve unique : traction d''abord) (2026-09-06)'
 where statut = 'actif' and md5(regle) = '640bb73a52af0c9a5d79763f7038c9f3';   -- #1

update doctrine set statut = 'obsolete',
  origine = origine || ' — corrigée : une obligation ne prouve aucune jambe (2026-09-06)'
 where statut = 'actif' and md5(regle) = '84917a0d49029b3672dd78528bd9f36b';   -- #6

update doctrine set statut = 'obsolete',
  origine = origine || ' — réécrite : référence morte « id 196 » retirée (2026-09-06)'
 where statut = 'actif' and md5(regle) = '01c47dfaa301aecac0b4fb5730bced66';   -- #9

update doctrine set statut = 'obsolete',
  origine = origine || ' — réécrite : devient la règle unique d''ordre de preuve (2026-09-06)'
 where statut = 'actif' and md5(regle) = '8b9b30d98fd8352f01efc2f926b66af3';   -- #512

update doctrine set statut = 'obsolete',
  origine = origine || ' — réécrite : référence morte « plafond de 001 » corrigée (2026-09-06)'
 where statut = 'actif' and md5(regle) = '028e889af21c4c4c34bcb309100c1d73';   -- #699

-- ------------------------------------------------------------
-- 2. Les remplaçantes, plus la règle neuve issue du diagnostic.
--    Bilan du plafond (doctrine #16, 25 actives max) : 25 - 5 + 5 = 25.
-- ------------------------------------------------------------
insert into doctrine (regle, origine, type, derniere_revision) values
 ('ORDRE DE PREUVE UNIQUE — TRACTION D''ABORD, TROU ENSUITE (absorbe la règle « trou FR d''abord », passée obsolete le 2026-09-06). Un lead n''entre dans prospection_clones QUE s''il porte déjà l''URL d''une preuve que des gens PAIENT le produit ailleurs (avis nombreux et datés sur une fiche payante, prix public affiché, MRR publié, revenus publiés) : c''est la jambe 0, le ticket d''entrée du vivier, posée par le récolteur avec saas_source + preuve_traction_us + source_traction_us + traction:PROUVÉ. L''Instructeur ne ré-instruit pas la traction : il ouvre l''URL, vérifie qu''elle dit ce qu''elle prétend, puis instruit trou FR → canal → WTP. Mesure 2026-09-06 sur les 31 dossiers de l''histoire de la base : 28/31 portaient une preuve du trou français, 4/31 seulement l''URL d''une preuve de traction, et 28/31 sont morts à la jambe trou_fr. Chercher un trou sans preuve de demande, c''est chercher un endroit où personne ne vend de pain en espérant que des gens y ont faim.',
  'seed 008 + diagnostic 2026-09-06 — absorbe la règle « trou FR d''abord »', 'garde_fou', '2026-09-06'),

 ('INTERDIT : le kill en amont de l''insertion. Un récolteur (Kiosque, Prospecteur, Rattrapage en mini-collecte) n''instruit JAMAIS le trou FR avant d''insérer et n''écarte jamais une idée pour trou réfuté — son unique filtre est la traction (pas d''URL de preuve de paiement, pas d''insertion). Deux raisons permanentes : (1) un kill non inséré ne laisse AUCUNE trace en base — ni condition_resurrection, ni matière pour le Fossoyeur, ni dédup, ni mémoire ; (2) le récolteur tue en une requête ce que l''Instructeur n''écarterait qu''après 8-10 min de recherche en français, sans que personne puisse vérifier son verdict. Mesure : consigne en vigueur du 2026-08-28 au 2026-09-06, résultat = Kiosque à 0 lead inséré à partir du 03/09, Instructeur à 7 runs consécutifs de vivier vide, Contre-avocat à 12 runs consécutifs de file vide, 0 attaque sur 9 jours sur 12.',
  'diagnostic 2026-09-06 — famine d''approvisionnement', 'garde_fou', '2026-09-06'),

 ('Une obligation réglementaire ne prouve AUCUNE jambe à elle seule. Elle prouve qu''un besoin existe, jamais qu''il est mal servi (le trou), ni qu''on peut l''atteindre en self-serve (le canal), ni que quelqu''un paie (la WTP). Elle est même un CONTRE-indice de trou : une échéance datée attire les éditeurs AVANT l''échéance (cf. la règle d''absorption). Mesure 2026-09-06 : le filon « obligation réglementaire FR/UE nommable » a produit 0 survivant sur 13 dossiers en une semaine, et 28 morts sur 31 depuis l''origine.',
  'run 2026-08-03 constat 2, corrigé le 2026-09-06', 'heuristique', '2026-09-06'),

 ('Catégories bannies (saturées/refutées, ne pas re-fouiller) : accessibilité Shopify (~120 apps) ; Omnibus prix 30j ; points relais ; passeport produit DPP (demande nulle constatée) ; collecte de documents clients FR (Doccollect, Superdocu, Wizidee, Clustdoc) ; extraction relevés bancaires (Parseur) ; résumé IA d''avis clients Shopify/Woo (≥5 acteurs) ; order printer/pick lists Shopify ; AI executive assistant généraliste ; lien-en-bio ; GEO/AI-visibility tracker.',
  'runs 2026-08-03→15, réécrite le 2026-09-06', 'heuristique', '2026-09-06'),

 ('Le SAS DE NOUVEAUTÉ (Product Hunt / Hacker News / nouveaux deals AppSumo) a deux usages distincts qu''il ne faut jamais confondre. (1) CHASSE AU LEAD : plafonné à 5 min, scan titres seulement, détection de convergences — le plafond de 5 min défini ici même reste intégralement en vigueur, parce qu''un flux de lancements ne porte aucune preuve de traction et que 95 % en est du bruit. (2) DIGEST DE LECTURE : alimenter `nouveautes` (nom, résumé bref, URL de la solution) pour la notification de 15:00. Le second usage n''autorise RIEN de plus pour le premier : un produit listé dans `nouveautes` n''est pas un candidat, et ne devient un lead que par le chemin normal, preuve de traction d''abord. Un produit n''entre qu''une fois — `unique (url)` — parce que reservir la nouveauté d''hier est le seul défaut qui rende un digest inutile.',
  'seed 009 (2026-09-03), référence corrigée le 2026-09-06', 'garde_fou', '2026-09-06')
on conflict do nothing;

-- ------------------------------------------------------------
-- Vérifications (à lancer à la main après application) :
--   select count(*) from doctrine where statut='actif';                              -- attendu : 25
--   select count(*) from doctrine where statut='actif' and regle like '%id 196%';     -- 0
--   select count(*) from doctrine where statut='actif' and regle like '%plafond de 001%'; -- 0
--   select count(*) from doctrine where statut='actif' and regle like 'Trou FR d%';   -- 0
-- ------------------------------------------------------------
