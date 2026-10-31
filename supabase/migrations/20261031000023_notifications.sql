-- LOT 11 : notifications.
-- Chaque événement crée une notification dans la boîte de réception de l'app (toujours disponible).
-- Le serveur l'envoie aussi sur le téléphone par Firebase Cloud Messaging quand le projet Firebase
-- est configuré (secret FCM_SERVICE_ACCOUNT), en respectant les heures calmes de l'utilisateur.

-- -----------------------------------------------------------------------------
-- Préférences
-- -----------------------------------------------------------------------------
alter table public.user_preferences
  add column notify_coupons  boolean not null default true,   -- coupons de la plateforme publiés
  add column notify_results  boolean not null default true,   -- résultat de mes coupons
  add column notify_tipsters boolean not null default true,   -- publications des Tipsters suivis
  add column notify_matches  boolean not null default true,   -- rappel 30 min avant un match d'une équipe suivie
  add column notify_morning  boolean not null default false,  -- rendez-vous du matin
  add column notify_credits  boolean not null default true,   -- crédits presque épuisés
  add column quiet_start     smallint not null default 23 check (quiet_start between 0 and 23),
  add column quiet_end       smallint not null default 7 check (quiet_end between 0 and 23);
grant update (notify_coupons, notify_results, notify_tipsters, notify_matches, notify_morning, notify_credits,
              quiet_start, quiet_end) on public.user_preferences to authenticated;

-- -----------------------------------------------------------------------------
-- Appareils (jetons FCM) et boîte de réception
-- -----------------------------------------------------------------------------
create table public.device_tokens (
  token        text primary key check (char_length(token) between 20 and 4096),
  user_id      uuid not null references auth.users(id) on delete cascade,
  platform     text not null default 'android' check (platform in ('android', 'ios')),
  app_version  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.notifications (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  kind          text not null check (kind in ('coupon', 'result', 'tipster', 'match', 'morning', 'credits', 'system')),
  title         text not null check (char_length(title) between 1 and 120),
  body          text not null check (char_length(body) <= 400),
  route         text,
  dedupe_key    text,
  created_at    timestamptz not null default now(),
  read_at       timestamptz,
  push_status   text not null default 'pending' check (push_status in ('pending', 'sent', 'skipped', 'failed', 'disabled')),
  push_attempts smallint not null default 0,
  push_error    text,
  send_after    timestamptz not null default now()
);
create unique index notifications_dedupe_idx on public.notifications (user_id, dedupe_key) where dedupe_key is not null;
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_push_idx on public.notifications (send_after) where push_status = 'pending';

revoke all on public.device_tokens, public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;
create policy "ses notifications" on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy "supprimer ses notifications" on public.notifications for delete to authenticated
  using (user_id = (select auth.uid()));

-- Un appareil appartient au dernier compte connecté dessus.
create or replace function public.register_device(p_token text, p_platform text default 'android', p_version text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  insert into public.device_tokens (token, user_id, platform, app_version)
  values (p_token, auth.uid(), coalesce(p_platform, 'android'), p_version)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform,
    app_version = excluded.app_version, updated_at = now();
end;
$$;

create or replace function public.unregister_device(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$ delete from public.device_tokens where token = p_token and user_id = auth.uid(); $$;

create or replace function public.mark_notifications_read(p_ids bigint[] default null)
returns integer
language sql
security definer
set search_path = ''
as $$
  with u as (
    update public.notifications set read_at = now()
    where user_id = auth.uid() and read_at is null and (p_ids is null or id = any(p_ids))
    returning 1)
  select count(*)::integer from u;
$$;

-- -----------------------------------------------------------------------------
-- Création d'une notification (préférences, heures calmes, sans doublon)
-- -----------------------------------------------------------------------------
-- Fin des heures calmes si l'utilisateur est dans sa plage (fuseau de son profil), sinon maintenant.
create or replace function app_private.quiet_until(p_user uuid, p_at timestamptz default now())
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz text;
  v_start integer;
  v_end integer;
  v_local timestamp;
  v_hour integer;
  v_quiet boolean;
  v_until timestamp;
begin
  select coalesce(p.timezone, 'Africa/Ouagadougou'), coalesce(up.quiet_start, 23), coalesce(up.quiet_end, 7)
    into v_tz, v_start, v_end
  from auth.users u
  left join public.profiles p on p.id = u.id
  left join public.user_preferences up on up.user_id = u.id
  where u.id = p_user;
  if v_tz is null or v_start = v_end then
    return p_at;
  end if;
  v_local := p_at at time zone v_tz;
  v_hour := extract(hour from v_local)::integer;
  v_quiet := case when v_start < v_end then v_hour >= v_start and v_hour < v_end
                  else v_hour >= v_start or v_hour < v_end end;
  if not v_quiet then
    return p_at;
  end if;
  v_until := date_trunc('day', v_local) + make_interval(hours => v_end);
  if v_until <= v_local then
    v_until := v_until + interval '1 day';
  end if;
  return v_until at time zone v_tz;
end;
$$;

create or replace function app_private.notify(p_user uuid, p_kind text, p_title text, p_body text,
                                              p_route text default null, p_dedupe text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prefs public.user_preferences;
  v_wanted boolean;
begin
  select * into v_prefs from public.user_preferences where user_id = p_user;
  v_wanted := case p_kind
        when 'coupon' then v_prefs.notify_coupons
        when 'result' then v_prefs.notify_results
        when 'tipster' then v_prefs.notify_tipsters
        when 'match' then v_prefs.notify_matches
        when 'morning' then v_prefs.notify_morning
        when 'credits' then v_prefs.notify_credits
        else true end;
  if not coalesce(v_wanted, true) then
    return;
  end if;
  insert into public.notifications (user_id, kind, title, body, route, dedupe_key, push_status, send_after)
  values (p_user, p_kind, left(p_title, 120), left(p_body, 400), p_route, p_dedupe,
          case when coalesce(v_prefs.notifications_enabled, true) and app_private.flag_on('notifications')
               then 'pending' else 'disabled' end,
          app_private.quiet_until(p_user))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

-- -----------------------------------------------------------------------------
-- Événements
-- -----------------------------------------------------------------------------
-- Coupon de la plateforme publié : aux utilisateurs qui peuvent le voir en entier.
create or replace function app_private.on_coupon_published()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
  r record;
begin
  if new.status <> 'published' or (tg_op = 'UPDATE' and old.status = 'published') or new.first_kickoff_at <= now() then
    return new;
  end if;
  select count(*) into v_n from public.coupon_selections where coupon_id = new.id;
  if v_n = 0 then
    return new;
  end if;
  for r in
    select up.user_id from public.user_preferences up join public.profiles p on p.id = up.user_id
    where up.notify_coupons and not p.is_suspended
      and app_private.can_see_coupon_selections(up.user_id, new.category, new.first_kickoff_at)
  loop
    perform app_private.notify(r.user_id, 'coupon', 'Nouveau coupon : ' || new.title,
      v_n || ' sélection' || case when v_n > 1 then 's' else '' end || ' · cote ' ||
      replace(to_char(new.total_odd, 'FM990.00'), '.', ',') || ' · premier match à ' ||
      to_char(new.first_kickoff_at at time zone 'Africa/Ouagadougou', 'HH24:MI') || '. Estimations, sans garantie.',
      '/coupon/' || new.id, 'coupon:' || new.id);
  end loop;
  return new;
end;
$$;
create trigger coupons_notify_published
  after insert or update of status on public.coupons
  for each row execute function app_private.on_coupon_published();

-- Résultat d'un coupon enregistré.
create or replace function app_private.on_user_coupon_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.result is null and new.result is not null and new.status = 'saved' then
    perform app_private.notify(new.user_id, 'result',
      case new.result when 'won' then 'Coupon gagné' when 'lost' then 'Coupon perdu' else 'Coupon annulé' end,
      '« ' || new.title || ' » : ' || case new.result
        when 'won' then 'gagné à la cote ' || replace(to_char(coalesce(new.settled_odd, new.total_odd), 'FM990.00'), '.', ',') || '.'
        when 'lost' then 'perdu. Le détail est dans Mes coupons.'
        else 'annulé (match non joué).' end,
      '/mes-coupons/' || new.id, 'result:' || new.id);
  end if;
  return new;
end;
$$;
create trigger user_coupons_notify_settled
  after update of result on public.user_coupons
  for each row execute function app_private.on_user_coupon_settled();

-- Publication d'un Tipster : à ses abonnés.
create or replace function app_private.on_post_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  r record;
begin
  select display_name into v_name from public.tipster_profiles where user_id = new.author_id;
  for r in select f.follower_id from public.tipster_followers f
           where f.tipster_id = new.author_id and not app_private.blocked_between(f.follower_id, new.author_id)
  loop
    perform app_private.notify(r.follower_id, 'tipster',
      v_name || case new.kind when 'coupon' then ' a publié un coupon' else ' a publié une analyse' end,
      coalesce(left(new.body, 140), 'Voir la publication et son résultat le moment venu.'),
      '/publication/' || new.id, 'post:' || new.id);
  end loop;
  return new;
end;
$$;
create trigger posts_notify_followers
  after insert on public.posts
  for each row execute function app_private.on_post_created();

-- Crédits presque épuisés (une fois par jour au plus).
create or replace function app_private.on_credits_low()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.plan_credits + old.extra_credits > 1 and new.plan_credits + new.extra_credits <= 1
     and not app_private.credits_exempt(new.user_id) then
    perform app_private.notify(new.user_id, 'credits', 'Crédits IA presque épuisés',
      'Il te reste ' || (new.plan_credits + new.extra_credits) || ' crédit. Ton forfait se recharge chaque mois ; des packs sont disponibles.',
      '/abonnement', 'credits:' || to_char(now(), 'YYYY-MM-DD'));
  end if;
  return new;
end;
$$;
create trigger credit_accounts_notify_low
  after update on public.credit_accounts
  for each row execute function app_private.on_credits_low();

-- Rappel 30 min avant un match d'une équipe suivie (appelé toutes les 5 min).
create or replace function app_private.notify_match_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select distinct f.user_id, m.id, h.name as home, a.name as away, m.kickoff_at, k.name as competition
    from public.matches m
    join public.teams h on h.id = m.home_team_id
    join public.teams a on a.id = m.away_team_id
    join public.competitions k on k.id = m.competition_id
    join public.user_favorites f on f.team_id in (m.home_team_id, m.away_team_id)
    where m.status = 'scheduled' and m.kickoff_at between now() + interval '20 minutes' and now() + interval '40 minutes'
  loop
    perform app_private.notify(r.user_id, 'match', r.home || ' – ' || r.away || ' à ' ||
      to_char(r.kickoff_at at time zone 'Africa/Ouagadougou', 'HH24:MI'),
      r.competition || ' : coup d''envoi dans 30 minutes. La fiche du match et ses cotes sont à jour.',
      '/match/' || r.id, 'match:' || r.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Rendez-vous du matin (07 h 30) et ménage des anciennes notifications.
create or replace function app_private.notify_morning()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := (now() at time zone 'Africa/Ouagadougou')::date;
  v_matches integer;
  v_featured text;
  v_coupon text;
  r record;
  v_count integer := 0;
begin
  delete from public.notifications where created_at < now() - interval '60 days';
  select count(*) into v_matches from public.matches m join public.competitions c on c.id = m.competition_id
  where c.is_active and (m.kickoff_at at time zone 'Africa/Ouagadougou')::date = v_day and m.status = 'scheduled';
  select h.name || ' – ' || a.name into v_featured
  from public.featured_matches f join public.matches m on m.id = f.match_id
  join public.teams h on h.id = m.home_team_id join public.teams a on a.id = m.away_team_id
  where f.day = v_day;
  select title into v_coupon from public.coupons
  where category = 'du_jour' and status = 'published' and (published_at at time zone 'Africa/Ouagadougou')::date = v_day
  order by published_at desc limit 1;
  if v_matches = 0 then
    return 0;
  end if;
  for r in select up.user_id from public.user_preferences up join public.profiles p on p.id = up.user_id
           where up.notify_morning and not p.is_suspended loop
    perform app_private.notify(r.user_id, 'morning', 'Ton rendez-vous du matin',
      v_matches || ' match' || case when v_matches > 1 then 's' else '' end || ' aujourd''hui'
      || coalesce(' · analyse offerte : ' || v_featured, '')
      || coalesce(' · ' || v_coupon || ' publié', '') || '.',
      '/accueil', 'morning:' || v_day);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- Envoi sur les téléphones : fonction push-dispatch (toutes les 2 minutes)
-- -----------------------------------------------------------------------------
create or replace function app_private.invoke_push_dispatch()
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
  if not exists (select 1 from public.notifications where push_status = 'pending' and send_after <= now()) then
    return null;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/push-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  ) into v_request;
  return v_request;
end;
$$;

revoke all on function app_private.quiet_until(uuid, timestamptz), app_private.notify(uuid, text, text, text, text, text),
  app_private.notify_match_reminders(), app_private.notify_morning(), app_private.invoke_push_dispatch()
  from public, anon, authenticated;
revoke all on function public.register_device(text, text, text), public.unregister_device(text),
  public.mark_notifications_read(bigint[]) from public, anon;
grant execute on function public.register_device(text, text, text), public.unregister_device(text),
  public.mark_notifications_read(bigint[]) to authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname) from cron.job
      where jobname in ('notify-match-reminders', 'notify-morning', 'push-dispatch');
    perform cron.schedule('notify-match-reminders', '*/5 * * * *', 'select app_private.notify_match_reminders()');
    perform cron.schedule('notify-morning', '30 7 * * *', 'select app_private.notify_morning()');
    perform cron.schedule('push-dispatch', '*/2 * * * *', 'select app_private.invoke_push_dispatch()');
  end if;
end;
$$;

update public.feature_flags set enabled = true where key = 'notifications';
