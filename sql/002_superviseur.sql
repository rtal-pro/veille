-- ============================================================
-- Migration 002 — Superviseur (audit + auto-correction mesurée)
-- À exécuter après 001. Idempotente.
-- ============================================================

create table if not exists audits (
  id bigint generated always as identity primary key,
  date_audit date not null default current_date,
  kpis jsonb,                 -- métriques chiffrées de la semaine (et rappel 28 j)
  diagnostic text,            -- LE goulot identifié, chiffres à l'appui
  recommandations text,       -- y compris hors-périmètre (constitution, architecture)
  created_at timestamptz not null default now()
);

create table if not exists modifications (
  id bigint generated always as identity primary key,
  date_proposition date not null default current_date,
  cible text not null,        -- fichier(s) modifié(s)
  resume text not null,
  hypothese text not null,    -- « si je change X, alors la métrique Y devrait… »
  metrique text not null,     -- ce qu'on mesure (ex. taux de survie, GO/sem)
  valeur_avant text,
  date_evaluation date not null,
  valeur_apres text,
  statut text not null default 'proposee'
    check (statut in ('proposee','en_evaluation','gardee','annulee','rejetee')),
  pr_url text,
  created_at timestamptz not null default now()
);

alter table audits         enable row level security;
alter table modifications  enable row level security;

-- Cycle de vie : proposee (PR ouverte) → en_evaluation (mergée, attend la date)
--   → gardee (métrique améliorée/stable) | annulee (dégradée → PR de revert)
--   ou rejetee (PR fermée par l'humain sans merge).

-- Vérification : select count(*) from audits; select count(*) from modifications;
