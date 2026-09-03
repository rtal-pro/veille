-- ============================================================
-- Migration 009 — Les nouveautés du jour (digest de lecture)
-- À exécuter après 008. Idempotente.
--
-- POURQUOI. Le système sait produire des LEADS instruits, attaqués, jugés.
-- Il ne sait pas produire une simple LISTE DE LECTURE : ce qui est sorti
-- hier, en une ligne, avec le lien. Ces produits, le Kiosque les voit déjà
-- tous les jours dans son sas de nouveauté PH/HN — et les laisse filer dans
-- ses notes en texte libre, d'où rien n'est requêtable. Mesure du 2026-09-03 :
-- `prospection_clones` ne contient que les 26 candidats RETENUS, `sources` ne
-- contient que des sites ; aucune table ne garde trace d'un produit croisé.
--
-- CE QUE CETTE TABLE N'EST PAS. Ce n'est pas un vivier de leads, et rien
-- n'oblige un produit listé ici à devenir un candidat. C'est un livrable de
-- LECTURE, servi dans la notification de 15:00 par la Lectrice. Le confondre
-- avec le vivier ferait retomber la doctrine du 2026-08-31 : un flux de
-- lancements n'apporte pas de preuve de traction, et ne peut donc pas fonder
-- un lead à lui seul.
--
-- LA GARDE ANTI-REDITE. `unique (url)` est la seule chose qui empêche de
-- reservir demain ce qui a été servi hier — un produit reste plusieurs jours
-- au classement Product Hunt. Elle est STRUCTURELLE et non déclarative : même
-- un agent qui oublie la consigne ne peut pas créer le doublon, la base le
-- refuse. `annonce_le` est le second verrou, et il répond à une autre
-- question : non pas « déjà vu ? » mais « déjà REÇU par l'humain ? ». Sans
-- lui, un matin où le pipeline part en retard (mémo écrit jusqu'à 12:06 UTC
-- selon la mesure du 2026-09-03), la Lectrice lirait avant la récolte, ne
-- montrerait rien, et ces lignes ne seraient plus « du jour » le lendemain :
-- récoltées, jamais lues, perdues. Preuve par mutation : tests/test_nouveautes.sh.
-- ============================================================

create table if not exists nouveautes (
  id           bigint generated always as identity primary key,
  date_recolte date not null default current_date,
  terrain      text not null,          -- producthunt | appsumo | …
  nom          text not null,          -- le nom de l'app, tel qu'affiché
  resume       text not null,          -- 1-2 phrases, ce que ça fait et pour qui
  url          text not null,          -- LA page de la solution, pas la page d'index
  annonce_le   date,                   -- null = jamais poussée vers l'humain
  created_at   timestamptz not null default now(),
  unique (url)
);

-- La requête de la Lectrice : « ce que je n'ai pas encore annoncé ».
create index if not exists idx_nouveautes_a_annoncer
  on nouveautes (date_recolte desc) where annonce_le is null;

alter table nouveautes enable row level security;

-- Accès agent_veille — gabarit de 006 : toute table doit figurer dans le GRANT
-- ET recevoir sa policy, sinon elle finit default-deny ou permission-denied.
-- Pas de DELETE : une nouveauté annoncée reste en base, c'est elle qui empêche
-- la redite. La purger reviendrait à désarmer la garde.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'agent_veille') then
    grant select, insert, update on nouveautes to agent_veille;
    grant usage, select on all sequences in schema public to agent_veille;
    drop policy if exists agent_veille_all on nouveautes;
    create policy agent_veille_all on nouveautes
      for all to agent_veille using (true) with check (true);
  end if;
end $$;

-- Doctrine : le sas de nouveauté a désormais DEUX usages, et il faut le dire.
-- NB : cette règle ne commence volontairement pas par « Product Hunt » —
-- tests/test_migrations.sh compte les règles actives commençant ainsi et en
-- attend exactement une (celle de 001, qui reste seule à porter le plafond
-- de la CHASSE). Renommer son début casserait ce test de dérive.
insert into doctrine (regle, type, origine) values
 ('Le SAS DE NOUVEAUTÉ (Product Hunt / Hacker News / nouveaux deals AppSumo) a deux usages distincts qu''il ne faut jamais confondre. (1) CHASSE AU LEAD : plafonné à 5 min, scan titres seulement, détection de convergences — le plafond de 001 reste intégralement en vigueur, parce qu''un flux de lancements ne porte aucune preuve de traction et que 95 % en est du bruit. (2) DIGEST DE LECTURE : alimenter `nouveautes` (nom, résumé bref, URL de la solution) pour la notification de 15:00. Le second usage n''autorise RIEN de plus pour le premier : un produit listé dans `nouveautes` n''est pas un candidat, et ne devient un lead que par le chemin normal, preuve de traction d''abord. Un produit n''entre qu''une fois — `unique (url)` — parce que reservir la nouveauté d''hier est le seul défaut qui rende un digest inutile.', 'garde_fou', '2026-09-03 digest des nouveautés')
on conflict do nothing;

-- Vérification : select terrain, count(*) from nouveautes group by terrain;
