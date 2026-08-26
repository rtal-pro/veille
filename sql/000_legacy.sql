-- ============================================================
-- Migration 000 — Tables legacy (schéma miroir de la prod) +
-- registre des blocs one-shot. Idempotente. Sur la prod ces
-- tables existent déjà : create if not exists = no-op.
-- ============================================================

create table if not exists migrations_appliquees (
  nom text primary key,
  applied_at timestamptz not null default now()
);

create table if not exists prospection_clones (
  id bigint generated always as identity primary key,
  date_run date not null default current_date,
  clone_nom text not null,
  saas_source text,
  secteur text,
  verdict text,                       -- v2.1: no default (006 purges legacy phantom 'GO')
  argument_decisif text,
  created_at timestamptz not null default now(),
  vague integer,
  job_to_be_done text,
  cible_client text,
  canal text,
  preuve_traction_us text,
  source_traction_us text,
  preuve_trou_fr text,
  concurrents_fr text,
  statut_jambes jsonb,
  pricing_us text,
  pricing_envisage text,
  risque_principal text,
  sources jsonb,
  notes text,
  pays_source text,
  marche_cible text default 'FR'
);
-- statut_pipeline, source_id, condition_resurrection, rapport_attaque,
-- score_atelier are added by 001 (kept there to mirror history).

create table if not exists veille_runs (
  id bigint generated always as identity primary key,
  date_run date not null default current_date,
  angles jsonb,
  sources_explorees jsonb,
  constats_methode text,
  candidats_inseres integer default 0,
  dont_go integer default 0,
  doublons_evites jsonb,
  notes text,
  created_at timestamptz not null default now(),
  agent text
);

create table if not exists analyses_go (
  id bigint generated always as identity primary key,
  prospection_id bigint references prospection_clones(id),
  date_run date not null default current_date,
  clone_nom text not null,
  statut text not null default 'complet',
  resume_executif text,
  analyse_technique text,
  architecture jsonb,
  build_plan jsonb,
  targeting jsonb,
  pricing jsonb,
  distribution jsonb,
  seo jsonb,
  geo jsonb,
  self_serve jsonb,
  concurrence jsonb,
  niveau_preuve jsonb,
  sources jsonb,
  rapport_md text,
  notes text,
  created_at timestamptz not null default now(),
  office_hours jsonb
);

alter table prospection_clones enable row level security;
alter table veille_runs enable row level security;
alter table analyses_go enable row level security;
alter table migrations_appliquees enable row level security;
