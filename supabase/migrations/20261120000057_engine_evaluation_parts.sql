-- Évaluation officielle poisson-3.0 découpée en lots (20/11/2026) : avec 28 compétitions et
-- 13 000 matchs, un seul appel dépassait la limite de calcul du serveur (16/11). Chaque lot
-- enregistre ici ses totaux ; le dernier lot additionne et enregistre l'évaluation, puis efface.
create table public.engine_evaluation_parts (
  run_id uuid not null,
  part integer not null check (part >= 0),
  parts integer not null check (parts > 0),
  engine_version text not null,
  payload jsonb,
  error text,
  created_at timestamptz not null default now(),
  primary key (run_id, part)
);
alter table public.engine_evaluation_parts enable row level security;
revoke all on public.engine_evaluation_parts from anon, authenticated;
comment on table public.engine_evaluation_parts is
  'Totaux intermédiaires de l''évaluation du moteur par lots (réservé au serveur, effacés à la fin).';
