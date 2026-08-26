-- ============================================================
-- Migration 005 — De la doctrine à la JURISPRUDENCE
-- Deux natures de règles : garde_fou (standards de preuve, non
-- négociables par les agents) vs heuristique (hypothèses empiriques
-- datées, soumises à falsification hebdomadaire). Idempotente.
-- ============================================================

alter table doctrine add column if not exists type text not null default 'heuristique';
alter table doctrine add column if not exists derniere_revision date;

do $$ begin
  alter table doctrine add constraint doctrine_type_chk
    check (type in ('garde_fou','heuristique'));
exception when duplicate_object then null; end $$;

-- Les standards de preuve et de fonctionnement sont des garde-fous,
-- pas des hypothèses sur le monde :
do $$
begin
  if not exists (select 1 from migrations_appliquees where nom = '005-typage') then
    update doctrine set type = 'garde_fou'
    where statut = 'actif' and (
         regle ilike '%aucun chiffre sans url%'
      or regle ilike '%télémétrie obligatoire%'
      or regle ilike '%réflexe mémoire%'
      or regle ilike '%plafond de doctrine%'
    );
    insert into migrations_appliquees (nom) values ('005-typage');
  end if;
end $$;

insert into doctrine (regle, origine, type) values
 ('La doctrine est une JURISPRUDENCE, pas un dogme : chaque règle heuristique est une hypothèse datée, issue de cas passés, candidate à la falsification hebdomadaire du Fossoyeur. Tout agent qui rencontre un fait prouvé (URL) contredisant une règle le JOURNALISE : c''est une contribution au système, jamais une infraction. Les garde-fous (standards de preuve), eux, ne changent que par l''humain.', '2026-08-21 jurisprudence', 'garde_fou')
on conflict do nothing;

-- Vérification : select type, count(*) from doctrine where statut='actif' group by 1;
