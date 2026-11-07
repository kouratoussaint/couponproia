-- LOT 25 (validé le 07/11) : sélection des championnats.
--  - Trois états : inactive (rien de synchronisé), observation (données chargées et visibles,
--    jamais dans un coupon automatique), active. is_active reste « données synchronisées »
--    (observation ou active), tenu à jour par un déclencheur : les tâches existantes ne changent pas.
--  - Catalogue du fournisseur (provider_leagues), rempli chaque semaine par la tâche « catalog ».
--  - Nom affiché « Nom (Pays) » quand deux compétitions suivies portent le même nom.
--  - Console : liste, recherche dans le catalogue, ajout (en observation, chargement immédiat),
--    état, ordre, forçage de qualité (super administrateur) ; tout est tracé dans audit_logs.

-- -----------------------------------------------------------------------------
-- État des compétitions
-- -----------------------------------------------------------------------------
alter table public.competitions
  add column status text not null default 'inactive' check (status in ('inactive', 'observation', 'active')),
  add column status_changed_at timestamptz,
  add column status_changed_by uuid references auth.users(id) on delete set null,
  add column display_name text,
  add column quality_override boolean not null default false,
  add column quality_override_by uuid references auth.users(id) on delete set null;
comment on column public.competitions.status is
  'inactive : non synchronisée ; observation : données chargées, visible, hors coupons automatiques ; active : coupons automatiques possibles';
comment on column public.competitions.is_active is 'Données synchronisées (status observation ou active), tenu à jour par déclencheur';
comment on column public.competitions.quality_override is
  'Forçage du super administrateur : compétition admise dans les coupons automatiques sans verdict positif du moteur';
create index competitions_status_changed_by_idx on public.competitions (status_changed_by);
create index competitions_quality_override_by_idx on public.competitions (quality_override_by);

update public.competitions set status = case when is_active then 'active' else 'inactive' end;

create or replace function app_private.competitions_sync_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- Ancien chemin d'insertion (is_active seul) : une compétition suivie devient active.
    if new.status = 'inactive' and new.is_active then
      new.status := 'active';
    end if;
  elsif new.status is not distinct from old.status and new.is_active is distinct from old.is_active then
    -- Ancien chemin de mise à jour (is_active seul).
    new.status := case when new.is_active then case when old.status = 'inactive' then 'active' else old.status end
                       else 'inactive' end;
  end if;
  new.is_active := new.status <> 'inactive';
  return new;
end;
$$;
revoke all on function app_private.competitions_sync_status() from public, anon, authenticated;
create trigger competitions_sync_status before insert or update on public.competitions
  for each row execute function app_private.competitions_sync_status();

-- Nom affiché : « Ligue 1 (Burkina-Faso) » dès que deux compétitions suivies portent le même nom.
create or replace function app_private.competition_label(p_id bigint)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when c.country is not null and c.country <> 'World' and exists (
      select 1 from public.competitions o
      where o.id <> c.id and o.status <> 'inactive' and lower(o.name) = lower(c.name))
    then c.name || ' (' || c.country || ')'
    else c.name end
  from public.competitions c where c.id = p_id;
$$;
revoke all on function app_private.competition_label(bigint) from public, anon, authenticated;

create or replace function app_private.refresh_competition_display_names()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.competitions c set display_name = app_private.competition_label(c.id)
  where c.display_name is distinct from app_private.competition_label(c.id);
  return null;
end;
$$;
revoke all on function app_private.refresh_competition_display_names() from public, anon, authenticated;
create trigger competitions_display_names after insert or update of name, country, status on public.competitions
  for each statement execute function app_private.refresh_competition_display_names();
update public.competitions c set display_name = app_private.competition_label(c.id);

-- -----------------------------------------------------------------------------
-- Catalogue du fournisseur (lecture par fonction, réservée à sports.configure)
-- -----------------------------------------------------------------------------
create table public.provider_leagues (
  provider_id     text not null references public.data_providers(id),
  provider_ref    text not null,
  name            text not null,
  type            text,
  country         text,
  country_code    text,
  logo_url        text,
  current_season  integer,
  seasons         jsonb not null default '[]'::jsonb,
  coverage        jsonb not null default '{}'::jsonb,
  refreshed_at    timestamptz not null default now(),
  primary key (provider_id, provider_ref)
);
alter table public.provider_leagues enable row level security;
revoke all on public.provider_leagues from anon, authenticated;

insert into public.app_settings (key, value, is_public, description) values
  ('sports.max_tracked_competitions', '40'::jsonb, false,
   'Nombre maximal de compétitions suivies (observation ou actives) : chacune coûte environ 14 requêtes API-Football par jour')
on conflict (key) do nothing;

insert into public.permissions (id, description) values
  ('competitions.override', 'Admettre une compétition dans les coupons automatiques sans verdict du moteur (super administrateur)')
on conflict (id) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id) values ('super_admin', 'competitions.override')
on conflict do nothing;

-- Décision du 03/11 : la CAN (22 matchs évalués, sous le seuil de 100) reste dans les coupons automatiques.
update public.competitions set quality_override = true where provider_id = 'api_football' and provider_ref = '6';
insert into public.audit_logs (actor_id, action, target_type, target_id, details)
select null, 'competition.override', 'competition', id::text,
       jsonb_build_object('to', true, 'reason', 'Décision du propriétaire du 03/11/2026 (LOT 25)')
from public.competitions where provider_id = 'api_football' and provider_ref = '6';

-- -----------------------------------------------------------------------------
-- Planification : catalogue chaque semaine, chargement ciblé d'une compétition ajoutée
-- -----------------------------------------------------------------------------
drop function app_private.invoke_sports_sync(text);
create or replace function app_private.invoke_sports_sync(p_job text, p_competition bigint default null)
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
  if p_job not in ('daily', 'odds', 'live', 'matchday', 'catalog') then
    raise exception 'Tâche inconnue : %', p_job using errcode = '22023';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice 'Vault indisponible : synchronisation % non lancée', p_job;
    return null;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    raise notice 'Secrets Vault absents : synchronisation % non lancée', p_job;
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/sports-sync',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := jsonb_build_object('job', p_job) || case when p_competition is null then '{}'::jsonb
                                                     else jsonb_build_object('competition_id', p_competition) end,
    timeout_milliseconds := 10000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_sports_sync(text, bigint) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.unschedule(jobname) from cron.job where jobname = 'sports-catalog';
    -- Lundi 03:10, avant l'évaluation du moteur (05:30).
    perform cron.schedule('sports-catalog', '10 3 * * 1', 'select app_private.invoke_sports_sync(''catalog'')');
  end if;
end;
$$;

-- Chargement immédiat d'une compétition ajoutée ; un échec d'appel n'annule pas l'action.
create or replace function app_private.request_competition_sync(p_id bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  return app_private.invoke_sports_sync('daily', p_id) is not null;
exception when others then
  raise notice 'Chargement de la compétition % non demandé : %', p_id, sqlerrm;
  return false;
end;
$$;
revoke all on function app_private.request_competition_sync(bigint) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Console
-- -----------------------------------------------------------------------------

-- Qualité du moteur par compétition (dernière évaluation, saisons regroupées, clés « id:saison »).
create or replace function app_private.competition_quality()
returns table (competition_id bigint, matches integer, brier_model numeric, brier_baseline numeric, verdict boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with ev as (
    select details -> 'per_competition_ids' as per from public.engine_evaluations order by created_at desc limit 1
  ), rows as (
    select split_part(e.key, ':', 1)::bigint as cid, (e.value ->> 'matches')::integer as n,
           (e.value ->> 'brierModel')::numeric as bm, (e.value ->> 'brierBaseline')::numeric as bb
    from ev, jsonb_each(coalesce(ev.per, '{}'::jsonb)) e
    where e.key ~ '^[0-9]+:[0-9]{4}$'
  )
  select cid, sum(n)::integer, round(sum(bm * n) / nullif(sum(n), 0), 5), round(sum(bb * n) / nullif(sum(n), 0), 5),
         case when sum(n) >= 100 then sum(bm * n) < sum(bb * n) end
  from rows group by cid;
$$;
revoke all on function app_private.competition_quality() from public, anon, authenticated;

-- Coupons non réglés (plateforme publiés, utilisateurs enregistrés) avec un match de la compétition.
create or replace function app_private.competition_open_coupons(p_id bigint)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select (
    select count(distinct c.id) from public.coupons c
    join public.coupon_selections s on s.coupon_id = c.id
    join public.matches m on m.id = s.match_id
    where m.competition_id = p_id and c.result is null and c.status = 'published'
  )::integer + (
    select count(distinct u.id) from public.user_coupons u
    join public.user_coupon_selections s on s.coupon_id = u.id
    join public.matches m on m.id = s.match_id
    where m.competition_id = p_id and u.result is null
  )::integer;
$$;
revoke all on function app_private.competition_open_coupons(bigint) from public, anon, authenticated;

create or replace function public.admin_competitions()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'sports.configure') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'display_name', coalesce(c.display_name, c.name),
      'country', c.country,
      'country_code', c.country_code,
      'logo_url', c.logo_url,
      'type', c.type,
      'provider_ref', c.provider_ref,
      'status', c.status,
      'priority', c.priority,
      'quality_override', c.quality_override,
      'current_season', c.current_season,
      'last_sync_at', c.verified_at,
      'status_changed_at', c.status_changed_at,
      'matches_14d', (select count(*) from public.matches m
                      where m.competition_id = c.id and m.status = 'scheduled'
                        and m.kickoff_at between now() and now() + interval '14 days'),
      'open_coupons', app_private.competition_open_coupons(c.id),
      'quality', (select jsonb_build_object('matches', q.matches, 'brier_model', q.brier_model,
                                            'brier_baseline', q.brier_baseline, 'verdict', q.verdict)
                  from app_private.competition_quality() q where q.competition_id = c.id)
    ) order by case c.status when 'active' then 0 when 'observation' then 1 else 2 end, c.priority, c.name)
    from public.competitions c
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_competitions() from public, anon;
grant execute on function public.admin_competitions() to authenticated;

create or replace function public.admin_search_league_catalog(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q text := lower(btrim(coalesce(p_query, '')));
begin
  if not app_private.has_permission(auth.uid(), 'sports.configure') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'catalog_size', (select count(*) from public.provider_leagues),
    'refreshed_at', (select max(refreshed_at) from public.provider_leagues),
    'results', coalesce((
      select jsonb_agg(r order by r ->> 'tracked' desc, r ->> 'name') from (
        select jsonb_build_object(
          'provider_ref', l.provider_ref,
          'name', l.name,
          'type', l.type,
          'country', l.country,
          'country_code', l.country_code,
          'logo_url', l.logo_url,
          'current_season', l.current_season,
          'coverage', l.coverage,
          'tracked', c.id is not null,
          'competition_id', c.id,
          'status', c.status
        ) as r
        from public.provider_leagues l
        left join public.competitions c on c.provider_id = l.provider_id and c.provider_ref = l.provider_ref
        where char_length(v_q) >= 2
          and (lower(l.name) like '%' || v_q || '%' or lower(coalesce(l.country, '')) like '%' || v_q || '%'
               or l.provider_ref = v_q)
        order by c.id is null, l.name
        limit 40
      ) s
    ), '[]'::jsonb));
end;
$$;
revoke all on function public.admin_search_league_catalog(text) from public, anon;
grant execute on function public.admin_search_league_catalog(text) to authenticated;

create or replace function public.admin_add_competition(p_provider_ref text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_league public.provider_leagues;
  v_existing public.competitions;
  v_id bigint;
  v_max integer := app_private.setting_int('sports.max_tracked_competitions', 40);
begin
  if not app_private.has_permission(v_actor, 'sports.configure') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  select * into v_league from public.provider_leagues
  where provider_id = 'api_football' and provider_ref = btrim(coalesce(p_provider_ref, ''));
  if not found then
    raise exception 'Compétition absente du catalogue : actualisez-le d''abord' using errcode = 'P0002';
  end if;
  select * into v_existing from public.competitions where provider_id = 'api_football' and provider_ref = v_league.provider_ref;
  if found and v_existing.status <> 'inactive' then
    raise exception 'Compétition déjà suivie' using errcode = '22023';
  end if;
  if (select count(*) from public.competitions where status <> 'inactive') >= v_max then
    raise exception 'Limite de compétitions suivies atteinte (sports.max_tracked_competitions)' using errcode = '54000';
  end if;
  if found then
    update public.competitions set status = 'observation', status_changed_at = now(), status_changed_by = v_actor
    where id = v_existing.id;
    v_id := v_existing.id;
  else
    insert into public.competitions (provider_id, provider_ref, name, country, country_code, logo_url, type,
                                     current_season, status, priority, status_changed_at, status_changed_by)
    values ('api_football', v_league.provider_ref, v_league.name, v_league.country, v_league.country_code,
            v_league.logo_url, case when v_league.type in ('league', 'cup') then v_league.type end,
            v_league.current_season, 'observation',
            (select coalesce(max(priority), 100) + 10 from public.competitions where priority < 1000),
            now(), v_actor)
    returning id into v_id;
  end if;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'competition.add', 'competition', v_id::text,
          jsonb_build_object('provider_ref', v_league.provider_ref, 'name', v_league.name, 'country', v_league.country));
  -- Saison en cours, classement et historique chargés tout de suite (environ 4 requêtes) ;
  -- sinon au passage quotidien de 4 h.
  perform app_private.request_competition_sync(v_id);
  return jsonb_build_object('id', v_id, 'status', 'observation');
end;
$$;
revoke all on function public.admin_add_competition(text) from public, anon;
grant execute on function public.admin_add_competition(text) to authenticated;

create or replace function public.admin_set_competition_status(p_id bigint, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.competitions;
  v_verdict boolean;
  v_warning text;
  v_open integer;
  v_max integer := app_private.setting_int('sports.max_tracked_competitions', 40);
begin
  if not app_private.has_permission(v_actor, 'sports.configure') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_status not in ('inactive', 'observation', 'active') then
    raise exception 'État inconnu' using errcode = '22023';
  end if;
  select * into v_old from public.competitions where id = p_id for update;
  if not found then
    raise exception 'Compétition inconnue' using errcode = 'P0002';
  end if;
  if v_old.status = p_status then
    return jsonb_build_object('status', p_status, 'warning', null);
  end if;
  if v_old.status = 'inactive'
     and (select count(*) from public.competitions where status <> 'inactive') >= v_max then
    raise exception 'Limite de compétitions suivies atteinte (sports.max_tracked_competitions)' using errcode = '54000';
  end if;
  select q.verdict into v_verdict from app_private.competition_quality() q where q.competition_id = p_id;
  if p_status = 'active' and v_verdict is distinct from true and not v_old.quality_override then
    v_warning := case when v_verdict is false
      then 'Le moteur ne fait pas mieux que la référence sur cette compétition : elle reste hors des coupons automatiques tant que ce verdict ne change pas.'
      else 'Pas encore de verdict du moteur (100 matchs évalués nécessaires) : elle reste hors des coupons automatiques jusqu''à l''évaluation du lundi.' end;
  end if;
  v_open := app_private.competition_open_coupons(p_id);
  update public.competitions set status = p_status, status_changed_at = now(), status_changed_by = v_actor where id = p_id;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'competition.status', 'competition', p_id::text,
          jsonb_build_object('from', v_old.status, 'to', p_status, 'verdict', v_verdict, 'open_coupons', v_open));
  if v_old.status = 'inactive' then
    perform app_private.request_competition_sync(p_id);
  end if;
  return jsonb_build_object('status', p_status, 'warning', v_warning, 'open_coupons', v_open);
end;
$$;
revoke all on function public.admin_set_competition_status(bigint, text) from public, anon;
grant execute on function public.admin_set_competition_status(bigint, text) to authenticated;

create or replace function public.admin_set_competition_priority(p_id bigint, p_priority integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old smallint;
begin
  if not app_private.has_permission(v_actor, 'sports.configure') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_priority is null or p_priority not between 0 and 999 then
    raise exception 'Ordre : nombre entier entre 0 et 999' using errcode = '22023';
  end if;
  select priority into v_old from public.competitions where id = p_id for update;
  if not found then
    raise exception 'Compétition inconnue' using errcode = 'P0002';
  end if;
  update public.competitions set priority = p_priority where id = p_id;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'competition.priority', 'competition', p_id::text, jsonb_build_object('from', v_old, 'to', p_priority));
end;
$$;
revoke all on function public.admin_set_competition_priority(bigint, integer) from public, anon;
grant execute on function public.admin_set_competition_priority(bigint, integer) to authenticated;

create or replace function public.admin_set_competition_override(p_id bigint, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old boolean;
begin
  if not app_private.has_permission(v_actor, 'competitions.override') then
    raise exception 'Action réservée au super administrateur' using errcode = '42501';
  end if;
  select quality_override into v_old from public.competitions where id = p_id for update;
  if not found then
    raise exception 'Compétition inconnue' using errcode = 'P0002';
  end if;
  update public.competitions set quality_override = coalesce(p_enabled, false),
         quality_override_by = case when p_enabled then v_actor end
  where id = p_id;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'competition.override', 'competition', p_id::text, jsonb_build_object('from', v_old, 'to', p_enabled));
end;
$$;
revoke all on function public.admin_set_competition_override(bigint, boolean) from public, anon;
grant execute on function public.admin_set_competition_override(bigint, boolean) to authenticated;
