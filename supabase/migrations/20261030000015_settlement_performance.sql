-- =============================================================================
-- Coupon Pro IA — LOT 8 — Règlement des coupons et statistiques de performance
-- Score à 90 minutes stocké à part (les paris se règlent sans prolongation), résultats des
-- sélections et des coupons (plateforme et utilisateurs), historique de chaque règlement et
-- de chaque correction, fonctions de statistiques, tâche planifiée.
-- =============================================================================

alter table public.matches
  add column ft_home_goals smallint,
  add column ft_away_goals smallint;

alter table public.coupons add column settled_odd numeric(9, 2);

alter table public.user_coupons
  add column result text check (result in ('won', 'lost', 'void')),
  add column settled_at timestamptz,
  add column settled_odd numeric(9, 2);
alter table public.user_coupon_selections
  add column result text check (result in ('won', 'lost', 'void'));

-- Historique de chaque règlement et de chaque correction (jamais d'effacement).
create table public.settlement_history (
  id                bigint generated always as identity primary key,
  coupon_kind       text not null check (coupon_kind in ('platform', 'user')),
  coupon_id         uuid not null,
  previous_result   text,
  new_result        text,
  previous_odd      numeric(9, 2),
  new_odd           numeric(9, 2),
  is_correction     boolean not null default false,
  selections        jsonb not null,
  created_at        timestamptz not null default now()
);
create index settlement_history_coupon_idx on public.settlement_history (coupon_kind, coupon_id, created_at);

revoke all on public.settlement_history from anon, authenticated;
grant select on public.settlement_history to authenticated;
alter table public.settlement_history enable row level security;
create policy "historique des règlements visibles" on public.settlement_history for select to authenticated
  using (
    (coupon_kind = 'platform' and exists (select 1 from public.coupons c where c.id = coupon_id))
    or (coupon_kind = 'user' and exists (select 1 from public.user_coupons u where u.id = coupon_id))
  );

update public.feature_flags set enabled = true where key = 'results_tracking';

-- -----------------------------------------------------------------------------
-- Statistiques : coupons de la plateforme (publiés avant le coup d'envoi uniquement)
-- Le rendement n'est calculé qu'avec une mise théorique explicite : 1 unité par coupon.
-- Sécurité de l'appelant : seules les données visibles par l'utilisateur sont lues.
-- -----------------------------------------------------------------------------
create or replace function public.platform_performance(p_days integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select c.* from public.coupons c
    where c.status = 'published'
      and c.published_at <= c.first_kickoff_at
      and (p_days is null or c.published_at >= now() - make_interval(days => p_days))
  ),
  settled as (select * from base where result in ('won', 'lost')),
  sels as (
    select s.*, c.result as coupon_result, comp.name as competition
    from public.coupon_selections s
    join base c on c.id = s.coupon_id
    join public.matches m on m.id = s.match_id
    join public.competitions comp on comp.id = m.competition_id
  )
  select jsonb_build_object(
    'scope', 'Coupons publiés par la plateforme avant le coup d''envoi' ||
             case when p_days is null then '' else ', ' || p_days || ' derniers jours' end,
    'coupons', (select count(*) from base),
    'won', (select count(*) from base where result = 'won'),
    'lost', (select count(*) from base where result = 'lost'),
    'void', (select count(*) from base where result = 'void'),
    'pending', (select count(*) from base where result is null),
    'withdrawn', (select count(*) from public.coupons where status = 'withdrawn'),
    'win_rate', (select round(count(*) filter (where result = 'won')::numeric / nullif(count(*), 0), 4) from settled),
    'average_odd', (select round(avg(total_odd), 2) from settled),
    'stake_note', 'Mise théorique de 1 unité par coupon (aucun pari réel)',
    'theoretical_return', (select round((coalesce(sum(settled_odd) filter (where result = 'won'), 0) - count(*)) / nullif(count(*), 0), 4) from settled),
    'by_category', coalesce((
      select jsonb_agg(x order by x->>'key') from (
        select jsonb_build_object('key', category, 'coupons', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost'),
          'win_rate', round(count(*) filter (where result = 'won')::numeric / nullif(count(*) filter (where result in ('won', 'lost')), 0), 4),
          'average_odd', round(avg(total_odd), 2)) as x
        from base group by category) t), '[]'::jsonb),
    'by_competition', coalesce((
      select jsonb_agg(x order by (x->>'selections')::int desc) from (
        select jsonb_build_object('key', competition, 'selections', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost'),
          'hit_rate', round(count(*) filter (where result = 'won')::numeric / nullif(count(*) filter (where result in ('won', 'lost')), 0), 4)) as x
        from sels group by competition) t), '[]'::jsonb),
    'by_market', coalesce((
      select jsonb_agg(x order by (x->>'selections')::int desc) from (
        select jsonb_build_object('key', market_code, 'selections', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost'),
          'hit_rate', round(count(*) filter (where result = 'won')::numeric / nullif(count(*) filter (where result in ('won', 'lost')), 0), 4),
          'average_model_probability', round(avg(model_probability), 4)) as x
        from sels group by market_code) t), '[]'::jsonb),
    'by_week', coalesce((
      select jsonb_agg(x order by x->>'week') from (
        select jsonb_build_object('week', to_char(date_trunc('week', published_at), 'YYYY-MM-DD'), 'coupons', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost')) as x
        from base group by date_trunc('week', published_at)) t), '[]'::jsonb),
    -- Calibration réelle : probabilité annoncée par le modèle contre taux de réussite constaté.
    'calibration', coalesce((
      select jsonb_agg(x order by x->>'bucket') from (
        select jsonb_build_object('bucket', floor(model_probability * 10) / 10, 'selections', count(*),
          'predicted', round(avg(model_probability), 3),
          'observed', round(count(*) filter (where result = 'won')::numeric / count(*), 3)) as x
        from sels where result in ('won', 'lost') group by floor(model_probability * 10)) t), '[]'::jsonb)
  );
$$;
revoke all on function public.platform_performance(integer) from public, anon;
grant execute on function public.platform_performance(integer) to authenticated;

-- Statistiques personnelles : coupons enregistrés par l'utilisateur (aucun pari réel).
create or replace function public.my_performance()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (select * from public.user_coupons where user_id = auth.uid() and status = 'saved'),
  settled as (select * from base where result in ('won', 'lost'))
  select jsonb_build_object(
    'scope', 'Vos coupons enregistrés (aucun pari réel)',
    'coupons', (select count(*) from base),
    'won', (select count(*) from base where result = 'won'),
    'lost', (select count(*) from base where result = 'lost'),
    'void', (select count(*) from base where result = 'void'),
    'pending', (select count(*) from base where result is null),
    'win_rate', (select round(count(*) filter (where result = 'won')::numeric / nullif(count(*), 0), 4) from settled),
    'average_odd', (select round(avg(total_odd), 2) from settled),
    'by_market', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object('key', s.market_code, 'selections', count(*),
          'won', count(*) filter (where s.result = 'won'), 'lost', count(*) filter (where s.result = 'lost')) as x
        from public.user_coupon_selections s join base b on b.id = s.coupon_id group by s.market_code) t), '[]'::jsonb),
    'by_week', coalesce((
      select jsonb_agg(x order by x->>'week') from (
        select jsonb_build_object('week', to_char(date_trunc('week', created_at), 'YYYY-MM-DD'), 'coupons', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost')) as x
        from base group by date_trunc('week', created_at)) t), '[]'::jsonb)
  );
$$;
revoke all on function public.my_performance() from public, anon;
grant execute on function public.my_performance() to authenticated;

-- -----------------------------------------------------------------------------
-- Tâche planifiée : règlement toutes les 30 minutes (après les scores en direct)
-- -----------------------------------------------------------------------------
create or replace function app_private.invoke_settlement()
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
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    raise notice 'Secrets Vault absents : règlement non lancé';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/settle-coupons',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_settlement() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('coupon-settle', '10,40 * * * *', 'select app_private.invoke_settlement()');
  else
    raise notice 'pg_cron ou pg_net absent : règlement non planifié';
  end if;
end;
$$;
