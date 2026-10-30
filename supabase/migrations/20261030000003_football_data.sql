-- =============================================================================
-- Coupon Pro IA — LOT 2 — Données football
-- Compétitions, équipes, matchs, classements, cotes résumées, journal des
-- synchronisations. Écritures réservées au serveur (Edge Function sports-sync,
-- rôle service) ; lecture pour les utilisateurs connectés.
-- =============================================================================

create table public.data_providers (
  id          text primary key check (id ~ '^[a-z_]+$'),
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table public.competitions (
  id              bigint generated always as identity primary key,
  provider_id     text not null references public.data_providers(id),
  provider_ref    text not null,
  name            text not null,
  country         text,
  country_code    text,
  logo_url        text,
  type            text check (type in ('league', 'cup')),
  current_season  integer check (current_season between 1990 and 2100),
  is_active       boolean not null default false,
  priority        smallint not null default 100,
  verified_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (provider_id, provider_ref)
);
create trigger competitions_set_updated_at
  before update on public.competitions
  for each row execute function app_private.set_updated_at();

create table public.teams (
  id            bigint generated always as identity primary key,
  provider_id   text not null references public.data_providers(id),
  provider_ref  text not null,
  name          text not null,
  logo_url      text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (provider_id, provider_ref)
);
create index teams_lower_name_idx on public.teams (lower(name));
create trigger teams_set_updated_at
  before update on public.teams
  for each row execute function app_private.set_updated_at();

create table public.matches (
  id                 bigint generated always as identity primary key,
  provider_id        text not null references public.data_providers(id),
  provider_ref       text not null,
  competition_id     bigint not null references public.competitions(id) on delete cascade,
  season             integer not null,
  round              text,
  kickoff_at         timestamptz not null,
  status             text not null check (status in (
                       'scheduled', 'live', 'finished', 'postponed', 'cancelled',
                       'abandoned', 'interrupted', 'awarded', 'unknown')),
  status_short       text,
  elapsed            smallint,
  home_team_id       bigint not null constraint matches_home_team_fk references public.teams(id),
  away_team_id       bigint not null constraint matches_away_team_fk references public.teams(id),
  home_goals         smallint,
  away_goals         smallint,
  ht_home_goals      smallint,
  ht_away_goals      smallint,
  venue              text,
  referee            text,
  source_updated_at  timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (provider_id, provider_ref),
  check (home_team_id <> away_team_id)
);
create index matches_kickoff_idx on public.matches (kickoff_at);
create index matches_competition_season_idx on public.matches (competition_id, season);
create index matches_home_idx on public.matches (home_team_id, kickoff_at desc);
create index matches_away_idx on public.matches (away_team_id, kickoff_at desc);
create index matches_status_kickoff_idx on public.matches (status, kickoff_at);
create trigger matches_set_updated_at
  before update on public.matches
  for each row execute function app_private.set_updated_at();

create table public.standings (
  competition_id  bigint not null references public.competitions(id) on delete cascade,
  season          integer not null,
  group_name      text not null default '',
  team_id         bigint not null references public.teams(id) on delete cascade,
  rank            smallint not null,
  points          smallint not null,
  played          smallint not null,
  win             smallint not null,
  draw            smallint not null,
  lose            smallint not null,
  goals_for       smallint not null,
  goals_against   smallint not null,
  goal_diff       smallint not null,
  form            text,
  description     text,
  home            jsonb,
  away            jsonb,
  updated_at      timestamptz not null default now(),
  primary key (competition_id, season, group_name, team_id)
);

-- Marchés normalisés (codes stables, indépendants du fournisseur)
create table public.markets (
  code        text primary key check (code ~ '^[A-Z0-9_]+$'),
  label       text not null,
  description text not null,
  sort        smallint not null default 100
);

-- Cotes résumées par issue : médiane et meilleure cote parmi les bookmakers du relevé.
create table public.odds_snapshots (
  id                bigint generated always as identity primary key,
  match_id          bigint not null references public.matches(id) on delete cascade,
  market_code       text not null references public.markets(code),
  outcome_code      text not null check (outcome_code ~ '^[A-Z0-9]+$'),
  line              numeric(4, 1),
  odd_median        numeric(7, 3) not null check (odd_median > 1),
  odd_best          numeric(7, 3) not null check (odd_best >= odd_median),
  bookmakers_count  smallint not null check (bookmakers_count > 0),
  captured_at       timestamptz not null default now()
);
create index odds_snapshots_match_idx on public.odds_snapshots (match_id, captured_at desc);

create view public.latest_odds
with (security_invoker = true) as
select distinct on (match_id, market_code, outcome_code, line)
  match_id, market_code, outcome_code, line, odd_median, odd_best, bookmakers_count, captured_at
from public.odds_snapshots
order by match_id, market_code, outcome_code, line, captured_at desc;

-- Journal des synchronisations (quota, erreurs, volumes)
create table public.sync_runs (
  id                  bigint generated always as identity primary key,
  provider_id         text not null references public.data_providers(id),
  job                 text not null,
  status              text not null default 'running'
                      check (status in ('running', 'success', 'partial', 'failed', 'skipped')),
  started_at          timestamptz not null default now(),
  finished_at         timestamptz,
  requests_used       integer not null default 0,
  requests_remaining  integer,
  items_upserted      integer not null default 0,
  error               text,
  details             jsonb not null default '{}'::jsonb
);
create index sync_runs_started_idx on public.sync_runs (started_at desc);

-- -----------------------------------------------------------------------------
-- Privilèges et RLS : lecture pour les connectés, écriture réservée au serveur
-- -----------------------------------------------------------------------------
revoke all on public.data_providers, public.competitions, public.teams, public.matches,
  public.standings, public.markets, public.odds_snapshots, public.latest_odds, public.sync_runs
from anon, authenticated;

grant select on public.competitions, public.teams, public.matches, public.standings,
  public.markets, public.odds_snapshots, public.latest_odds, public.sync_runs,
  public.data_providers
to authenticated;

alter table public.data_providers  enable row level security;
alter table public.competitions    enable row level security;
alter table public.teams           enable row level security;
alter table public.matches         enable row level security;
alter table public.standings       enable row level security;
alter table public.markets         enable row level security;
alter table public.odds_snapshots  enable row level security;
alter table public.sync_runs       enable row level security;

create policy "compétitions lisibles" on public.competitions for select to authenticated using (true);
create policy "équipes lisibles"      on public.teams        for select to authenticated using (true);
create policy "matchs lisibles"       on public.matches      for select to authenticated using (true);
create policy "classements lisibles"  on public.standings    for select to authenticated using (true);
create policy "marchés lisibles"      on public.markets      for select to authenticated using (true);
create policy "cotes lisibles"        on public.odds_snapshots for select to authenticated using (true);

create policy "fournisseurs : gestionnaires" on public.data_providers
  for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'sports.configure'));
create policy "synchronisations : gestionnaires" on public.sync_runs
  for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'sports.configure'));

-- -----------------------------------------------------------------------------
-- Données de référence
-- -----------------------------------------------------------------------------
insert into public.data_providers (id, name) values ('api_football', 'API-Football (api-sports.io)')
on conflict (id) do nothing;

insert into public.markets (code, label, description, sort) values
  ('1X2',  'Résultat du match',          'Victoire domicile (1), nul (X) ou victoire extérieur (2)', 10),
  ('DC',   'Double chance',              'Deux issues sur trois : 1X, 12 ou X2', 20),
  ('OU',   'Plus / moins de buts',       'Nombre total de buts au-dessus ou au-dessous d''une ligne', 30),
  ('BTTS', 'Les deux équipes marquent',  'Chaque équipe marque au moins un but', 40)
on conflict (code) do update set label = excluded.label, description = excluded.description, sort = excluded.sort;

-- Compétitions suivies au départ (décision D8). Les identifiants sont ceux d'API-Football ;
-- le nom, le pays, le logo et la saison en cours sont réécrits et vérifiés à la
-- première synchronisation (verified_at). Une compétition inconnue reste non vérifiée.
insert into public.competitions (provider_id, provider_ref, name, is_active, priority) values
  ('api_football', '39',  'Premier League',          true, 10),
  ('api_football', '140', 'La Liga',                 true, 20),
  ('api_football', '135', 'Serie A',                 true, 30),
  ('api_football', '78',  'Bundesliga',              true, 40),
  ('api_football', '61',  'Ligue 1',                 true, 50),
  ('api_football', '2',   'UEFA Champions League',   true, 5),
  ('api_football', '3',   'UEFA Europa League',      true, 60),
  ('api_football', '6',   'Coupe d''Afrique des nations', true, 4),
  ('api_football', '12',  'CAF Champions League',    true, 70)
on conflict (provider_id, provider_ref) do nothing;

insert into public.feature_flags (key, enabled, description) values
  ('matches', true, 'Matchs, compétitions, classements et cotes (LOT 2)')
on conflict (key) do nothing;

-- Réglages privés de la synchronisation (modifiables par l'administration)
insert into public.app_settings (key, value, is_public, description) values
  ('sports.daily_request_budget', '95'::jsonb, false,
   'Requêtes API-Football maximum par jour (95 pour l''offre gratuite à 100, ~7000 pour Pro)'),
  ('sports.odds_window_hours', '48'::jsonb, false,
   'Fenêtre (heures) des matchs à venir dont on relève les cotes'),
  ('sports.odds_max_fixtures_per_run', '12'::jsonb, false,
   'Nombre maximum de matchs dont on relève les cotes à chaque passage'),
  ('sports.live_lookback_hours', '3'::jsonb, false,
   'Matchs commencés depuis moins de N heures et non terminés : suivis en direct')
on conflict (key) do nothing;
