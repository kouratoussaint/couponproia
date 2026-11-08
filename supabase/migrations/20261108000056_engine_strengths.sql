-- LOT 28 (moteur poisson-3.0) : « forces du jour » calculées chaque heure sur tous les matchs
-- terminés (toutes compétitions), lues par les analyses et le générateur de coupons.
-- Table réservée au serveur (aucun accès depuis l'application).
create table public.engine_strengths (
  id bigint generated always as identity primary key,
  engine_version text not null,
  computed_at timestamptz not null default now(),
  matches integer not null check (matches >= 0),
  data jsonb not null
);
create index engine_strengths_latest on public.engine_strengths (engine_version, computed_at desc);
alter table public.engine_strengths enable row level security;
revoke all on public.engine_strengths from anon, authenticated;
comment on table public.engine_strengths is
  'Moteur poisson-3.0 : forces des équipes, moyennes des compétitions et niveaux des championnats (photo horaire).';

create or replace function app_private.invoke_engine_strengths()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_request bigint;
begin
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice 'Vault absent : forces non calculées';
    return null;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    raise notice 'Secrets Vault absents : forces non calculées';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/engine-evaluate',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{"job":"strengths"}'::jsonb,
    timeout_milliseconds := 60000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_engine_strengths() from public, anon, authenticated;

-- Évaluation officielle d'un moteur précis (bascule vers poisson-3.0 : évaluation d'abord).
create or replace function app_private.invoke_engine_evaluation_for(p_engine text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_request bigint;
begin
  if p_engine is null or p_engine !~ '^poisson-[0-9]+\.[0-9]+$' then
    raise exception 'moteur invalide' using errcode = '22023';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    return null;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/engine-evaluate',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := jsonb_build_object('engine', p_engine),
    timeout_milliseconds := 150000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_engine_evaluation_for(text) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('engine-strengths-hourly', '7 * * * *', 'select app_private.invoke_engine_strengths()');
  else
    raise notice 'pg_cron ou pg_net absent : forces horaires non planifiées';
  end if;
end;
$$;
