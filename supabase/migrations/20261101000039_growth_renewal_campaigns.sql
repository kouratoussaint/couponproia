-- LOT 18 (01/11) : liens de partage (B6), renouvellement facilité (D4), conversion et rétention
-- (E1), notifications ciblées (E2).

-- -----------------------------------------------------------------------------
-- Téléchargement public des APK (le dépôt GitHub est privé : ses releases ne sont pas publiques)
-- -----------------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('downloads', 'downloads', true, 52428800, array['application/vnd.android.package-archive'])
  on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
                                 allowed_mime_types = excluded.allowed_mime_types;
end;
$$;

insert into public.permissions (id, description) values
  ('campaigns.send', 'Envoyer des notifications ciblées (super administrateur)'),
  ('growth.read', 'Voir la conversion et la rétention des utilisateurs')
on conflict (id) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id) values
  ('super_admin', 'campaigns.send'), ('super_admin', 'growth.read')
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Notifications : forfait (renouvellement) et annonces
-- -----------------------------------------------------------------------------
alter table public.user_preferences add column notify_news boolean not null default true;
grant update (notify_news) on public.user_preferences to authenticated;

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('coupon', 'result', 'tipster', 'match', 'morning', 'credits', 'system', 'odds', 'budget',
                  'analysis', 'reminder', 'live', 'billing', 'news'));

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
        when 'odds' then v_prefs.notify_coupons
        when 'result' then v_prefs.notify_results
        when 'tipster' then v_prefs.notify_tipsters
        when 'match' then v_prefs.notify_matches
        when 'morning' then v_prefs.notify_morning
        when 'credits' then v_prefs.notify_credits
        when 'billing' then v_prefs.notify_credits
        when 'analysis' then v_prefs.notify_analyses
        when 'reminder' then v_prefs.notify_bet_reminders
        when 'live' then v_prefs.notify_live
        when 'news' then v_prefs.notify_news
        else true end;  -- budget, system : toujours (jeu responsable, exploitation)
  if not coalesce(v_wanted, true) then
    return;
  end if;
  insert into public.notifications (user_id, kind, title, body, route, dedupe_key, push_status, send_after)
  values (p_user, p_kind, left(p_title, 120), left(p_body, 400), p_route, p_dedupe,
          case when coalesce(v_prefs.notifications_enabled, true) and app_private.flag_on('notifications')
               then 'pending' else 'disabled' end,
          case when p_kind in ('budget', 'system', 'live', 'reminder') then now() else app_private.quiet_until(p_user) end)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;
revoke all on function app_private.notify(uuid, text, text, text, text, text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- E1. Jours d'activité (ouverture de l'app), base de la rétention
-- -----------------------------------------------------------------------------
create table public.user_activity_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null,
  primary key (user_id, day)
);
create index user_activity_days_day_idx on public.user_activity_days (day);
revoke all on public.user_activity_days from anon, authenticated;
alter table public.user_activity_days enable row level security;

-- Appelée par l'app à l'ouverture (une fois par jour suffit).
create or replace function public.touch_activity()
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.user_activity_days (user_id, day)
  select auth.uid(), app_private.local_today() where auth.uid() is not null
  on conflict do nothing;
$$;
revoke all on function public.touch_activity() from public, anon;
grant execute on function public.touch_activity() to authenticated;

-- Reprise de l'historique à partir des traces existantes.
insert into public.user_activity_days (user_id, day)
select distinct user_id, (ts at time zone coalesce((select value #>> '{}' from public.app_settings where key = 'app.timezone'), 'UTC'))::date
from (
  select user_id, created_at as ts from public.ai_requests where user_id is not null
  union all select user_id, created_at from public.assistant_messages where user_id is not null
  union all select user_id, created_at from public.bet_journal
  union all select user_id, read_at from public.notifications where read_at is not null
  union all select user_id, updated_at from public.device_tokens where user_id is not null
  union all select id, (to_jsonb(u) ->> 'last_sign_in_at')::timestamptz from auth.users u
            where (to_jsonb(u) ->> 'last_sign_in_at') is not null
  union all select id, created_at from auth.users
) t
where exists (select 1 from auth.users u where u.id = t.user_id)
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- B6. Ouvertures de liens partagés (sans donnée personnelle)
-- -----------------------------------------------------------------------------
create table public.share_clicks (
  id         bigint generated always as identity primary key,
  kind       text not null check (kind in ('coupon', 'match')),
  target     text not null check (char_length(target) <= 64),
  android    boolean not null,
  created_at timestamptz not null default now()
);
create index share_clicks_created_idx on public.share_clicks (created_at);
revoke all on public.share_clicks from anon, authenticated;
alter table public.share_clicks enable row level security;

-- -----------------------------------------------------------------------------
-- D4. Renouvellement
-- -----------------------------------------------------------------------------
-- Dernier forfait payant de l'utilisateur s'il se termine dans 3 jours ou s'est terminé il y a moins de
-- 7 jours (sans forfait plus long derrière) : de quoi proposer « Renouveler » en un geste.
create or replace function public.my_renewal()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when s.period_end between now() - interval '7 days' and now() + interval '3 days' then
    jsonb_build_object('plan_code', s.plan_code, 'period', coalesce(p.period, 'monthly'),
                       'period_end', s.period_end, 'ended', s.period_end <= now())
  end
  from (select * from public.subscriptions where user_id = auth.uid() and plan_code <> 'FREE'
        order by period_end desc limit 1) s
  left join public.payments p on p.id = s.payment_id;
$$;
revoke all on function public.my_renewal() from public, anon;
grant execute on function public.my_renewal() to authenticated;

-- Rappels quotidiens : 3 jours avant, la veille, le lendemain de la fin du forfait.
create or replace function app_private.notify_renewals()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
  v_step text;
  v_date text;
begin
  for r in
    select distinct on (s.user_id) s.id, s.user_id, s.plan_code, s.period_end, coalesce(p.period, 'monthly') as period
    from public.subscriptions s
    left join public.payments p on p.id = s.payment_id
    join public.profiles pr on pr.id = s.user_id and not pr.is_suspended
    where s.plan_code <> 'FREE' and s.period_end > now() - interval '2 days'
    order by s.user_id, s.period_end desc
  loop
    v_step := case
      when r.period_end between now() + interval '2 days' and now() + interval '3 days' then 'j-3'
      when r.period_end between now() and now() + interval '1 day' then 'j-1'
      when r.period_end between now() - interval '1 day' and now() then 'j+1'
    end;
    continue when v_step is null;
    v_date := to_char(r.period_end at time zone 'Africa/Ouagadougou', 'DD/MM à HH24:MI');
    perform app_private.notify(r.user_id, 'billing',
      case v_step when 'j+1' then 'Votre forfait ' || r.plan_code || ' a pris fin'
                  else 'Votre forfait ' || r.plan_code || ' se termine bientôt' end,
      case v_step when 'j+1' then 'Il s''est terminé le ' || v_date || '. Touchez pour le renouveler en un geste.'
                  else 'Fin le ' || v_date || '. Renouvelez en un geste pour garder tous vos coupons et analyses.' end,
      '/abonnement?renouveler=' || r.plan_code || '&periode=' || r.period,
      'renew:' || r.id || ':' || v_step);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function app_private.notify_renewals() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- E2. Segments et notifications ciblées
-- -----------------------------------------------------------------------------
create or replace function app_private.segment_users(p_segment text)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id from public.profiles p
  where not p.is_suspended
    and case p_segment
      when 'all' then true
      when 'free' then app_private.plan_of(p.id) = 'FREE'
      when 'paying' then app_private.plan_of(p.id) <> 'FREE'
      when 'expiring' then exists (select 1 from public.subscriptions s where s.user_id = p.id and s.plan_code <> 'FREE'
                                   and s.period_end between now() and now() + interval '7 days')
                       and not exists (select 1 from public.subscriptions s where s.user_id = p.id
                                       and s.period_end > now() + interval '7 days')
      when 'expired' then app_private.plan_of(p.id) = 'FREE'
                      and exists (select 1 from public.subscriptions s where s.user_id = p.id and s.plan_code <> 'FREE'
                                  and s.period_end between now() - interval '30 days' and now())
      when 'never_paid' then not exists (select 1 from public.payments pay where pay.user_id = p.id
                                         and pay.status = 'succeeded')
      when 'inactive_7d' then p.created_at < now() - interval '7 days'
                          and not exists (select 1 from public.user_activity_days a where a.user_id = p.id
                                          and a.day > app_private.local_today() - 7)
      else false end;
$$;
revoke all on function app_private.segment_users(text) from public, anon, authenticated;

create table public.push_campaigns (
  id          bigint generated always as identity primary key,
  segment     text not null,
  title       text not null check (char_length(title) between 3 and 80),
  body        text not null check (char_length(body) between 3 and 300),
  route       text not null,
  audience    integer not null,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index push_campaigns_created_idx on public.push_campaigns (created_at desc);
create index push_campaigns_created_by_idx on public.push_campaigns (created_by);
revoke all on public.push_campaigns from anon, authenticated;
grant select on public.push_campaigns to authenticated;
alter table public.push_campaigns enable row level security;
create policy "campagnes : lecture" on public.push_campaigns for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'campaigns.send'));

create or replace function public.admin_campaign_audience(p_segment text)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'campaigns.send') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return (select count(*) from app_private.segment_users(p_segment));
end;
$$;
revoke all on function public.admin_campaign_audience(text) from public, anon;
grant execute on function public.admin_campaign_audience(text) to authenticated;

create or replace function public.admin_send_campaign(p_segment text, p_title text, p_body text, p_route text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_id bigint;
  v_n integer := 0;
  v_user uuid;
begin
  if not app_private.has_permission(v_actor, 'campaigns.send') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_segment not in ('all', 'free', 'paying', 'expiring', 'expired', 'never_paid', 'inactive_7d') then
    raise exception 'Segment inconnu' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 80 or char_length(btrim(coalesce(p_body, ''))) not between 3 and 300 then
    raise exception 'Titre (3 à 80 caractères) et message (3 à 300) obligatoires' using errcode = '22023';
  end if;
  if app_private.has_forbidden_words(p_title || ' ' || p_body) then
    raise exception 'Mot interdit (sûr, garanti, assuré, gain, sans risque, 100 %%…) : les estimations ne sont jamais des promesses'
      using errcode = '22023';
  end if;
  if p_route not in ('/accueil', '/coupons', '/matchs', '/assistant', '/abonnement', '/carnet', '/performances',
                     '/communaute', '/laboratoire') then
    raise exception 'Destination non autorisée' using errcode = '22023';
  end if;
  if (select count(*) from public.push_campaigns where created_at > now() - interval '24 hours') >= 3 then
    raise exception 'Trois envois par 24 heures au plus, pour ne pas lasser les utilisateurs' using errcode = '54000';
  end if;
  insert into public.push_campaigns (segment, title, body, route, audience, created_by)
  values (p_segment, btrim(p_title), btrim(p_body), p_route, 0, v_actor) returning id into v_id;
  for v_user in select * from app_private.segment_users(p_segment) loop
    perform app_private.notify(v_user, 'news', btrim(p_title), btrim(p_body), p_route, 'campaign:' || v_id);
    v_n := v_n + 1;
  end loop;
  update public.push_campaigns set audience = v_n where id = v_id;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'campaign.send', 'push_campaign', v_id::text,
          jsonb_build_object('segment', p_segment, 'title', p_title, 'audience', v_n));
  return v_n;
end;
$$;
revoke all on function public.admin_send_campaign(text, text, text, text) from public, anon;
grant execute on function public.admin_send_campaign(text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- E1. Conversion et rétention
-- -----------------------------------------------------------------------------
create or replace function public.admin_growth(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 7), 365);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_today date := app_private.local_today();
begin
  if not app_private.has_permission(auth.uid(), 'growth.read') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return (
    with cohort as (
      select u.id, u.created_at from auth.users u where u.created_at >= v_from
    ),
    paid as (
      select user_id, min(coalesce(paid_at, created_at)) as first_paid, count(*) filter (where kind = 'subscription') as subs
      from public.payments where status = 'succeeded' group by user_id
    )
    select jsonb_build_object(
      'days', v_days,
      'funnel', jsonb_build_object(
        'signed_up', (select count(*) from cohort),
        'onboarded', (select count(*) from cohort c join public.user_preferences up on up.user_id = c.id
                      where up.onboarded_at is not null),
        'came_back', (select count(*) from cohort c where exists (
                        select 1 from public.user_activity_days a where a.user_id = c.id
                        and a.day > (c.created_at at time zone 'UTC')::date)),
        'first_purchase', (select count(*) from cohort c join paid p on p.user_id = c.id),
        'renewed', (select count(*) from cohort c join paid p on p.user_id = c.id where p.subs >= 2)
      ),
      'period', jsonb_build_object(
        'new_paying', (select count(*) from paid where first_paid >= v_from),
        'renewals', (select count(*) from public.payments pay
                     where pay.status = 'succeeded' and pay.kind = 'subscription'
                       and coalesce(pay.paid_at, pay.created_at) >= v_from
                       and exists (select 1 from public.payments prev where prev.user_id = pay.user_id
                                   and prev.status = 'succeeded' and prev.kind = 'subscription'
                                   and coalesce(prev.paid_at, prev.created_at) < coalesce(pay.paid_at, pay.created_at))),
        'revenue_xof', (select coalesce(sum(amount_xof), 0) from public.payments
                        where status = 'succeeded' and refunded_at is null and coalesce(paid_at, created_at) >= v_from),
        'paying_now', (select count(*) from public.profiles p where app_private.plan_of(p.id) <> 'FREE'),
        'users_total', (select count(*) from public.profiles),
        'share_opens', (select count(*) from public.share_clicks where created_at >= v_from),
        'share_opens_android', (select count(*) from public.share_clicks where created_at >= v_from and android)
      ),
      'active', jsonb_build_object(
        'day', (select count(distinct user_id) from public.user_activity_days where day = v_today),
        'week', (select count(distinct user_id) from public.user_activity_days where day > v_today - 7),
        'month', (select count(distinct user_id) from public.user_activity_days where day > v_today - 30)
      ),
      -- Cohortes hebdomadaires (8 dernières semaines) : part des inscrits revenus 7 et 30 jours après.
      'cohorts', coalesce((
        select jsonb_agg(x order by x->>'week') from (
          select jsonb_build_object(
            'week', to_char(w.week, 'YYYY-MM-DD'),
            'users', count(*),
            'd7_eligible', count(*) filter (where u.created_at <= now() - interval '7 days'),
            'd7', count(*) filter (where u.created_at <= now() - interval '7 days' and exists (
                    select 1 from public.user_activity_days a where a.user_id = u.id
                    and a.day >= (u.created_at at time zone 'UTC')::date + 7)),
            'd30_eligible', count(*) filter (where u.created_at <= now() - interval '30 days'),
            'd30', count(*) filter (where u.created_at <= now() - interval '30 days' and exists (
                    select 1 from public.user_activity_days a where a.user_id = u.id
                    and a.day >= (u.created_at at time zone 'UTC')::date + 30)),
            'paid', count(*) filter (where exists (select 1 from paid p where p.user_id = u.id))
          ) as x
          from auth.users u
          cross join lateral (select date_trunc('week', u.created_at) as week) w
          where u.created_at >= date_trunc('week', now()) - interval '7 weeks'
          group by w.week) t), '[]'::jsonb)
    )
  );
end;
$$;
revoke all on function public.admin_growth(integer) from public, anon;
grant execute on function public.admin_growth(integer) to authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname) from cron.job where jobname = 'notify-renewals';
    perform cron.schedule('notify-renewals', '41 8 * * *', 'select app_private.notify_renewals()');
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Cohérence des coupons avec l'analyse IA (demande du 01/11)
-- -----------------------------------------------------------------------------
insert into public.permissions (id, description) values
  ('coupons.edit', 'Modifier un coupon généré avant sa publication, dupliquer un coupon retiré (super administrateur)')
on conflict (id) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id) values ('super_admin', 'coupons.edit')
on conflict do nothing;

alter table public.coupons add column ai_override boolean not null default false;
comment on column public.coupons.ai_override is
  'Vrai quand l''équipe a maintenu une sélection contraire à l''analyse IA (validation, modification ou publication forcée)';

-- Validation humaine d'un coupon à revoir : le choix de l'équipe prime sur le contrôle IA.
create or replace function app_private.coupon_human_approval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'pending_review' and new.status = 'ready' and auth.uid() is not null then
    new.ai_override := true;
  end if;
  return new;
end;
$$;
create trigger coupons_human_approval before update of status on public.coupons
  for each row execute function app_private.coupon_human_approval();
revoke all on function app_private.coupon_human_approval() from public, anon, authenticated;

-- Pronostic de l'IA contredit par une sélection (même famille de marché), ou null.
-- Une sélection est cohérente si elle passe chaque fois que le pronostic se réalise.
create or replace function app_private.ai_contradiction(p_selection text, p_analysis jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_pick text;
  v_sel_set text[];
  v_pick_set text[];
  v_sel_fam text := split_part(p_selection, '.', 1);
begin
  if p_analysis is null or coalesce(p_analysis ->> 'recommandation_possible', 'false') <> 'true' then
    return null;
  end if;
  for v_pick in select e ->> 'cle' from jsonb_array_elements(coalesce(p_analysis -> 'marches_envisageables', '[]'::jsonb)) e
                where e ->> 'cle' is not null loop
    if v_sel_fam in ('1X2', 'DC') and split_part(v_pick, '.', 1) in ('1X2', 'DC') then
      v_sel_set := case p_selection when '1X2.HOME' then '{H}' when '1X2.DRAW' then '{D}' when '1X2.AWAY' then '{A}'
                     when 'DC.1X' then '{H,D}' when 'DC.X2' then '{D,A}' when 'DC.12' then '{H,A}' end;
      v_pick_set := case v_pick when '1X2.HOME' then '{H}' when '1X2.DRAW' then '{D}' when '1X2.AWAY' then '{A}'
                      when 'DC.1X' then '{H,D}' when 'DC.X2' then '{D,A}' when 'DC.12' then '{H,A}' end;
      if v_sel_set is not null and v_pick_set is not null and not (v_pick_set <@ v_sel_set) then
        return v_pick;
      end if;
    elsif v_sel_fam = 'OU' and split_part(v_pick, '.', 1) = 'OU' then
      if split_part(p_selection, '.', 2) <> split_part(v_pick, '.', 2)
         or (split_part(p_selection, '.', 2) = 'OVER'
             and substr(p_selection, 9)::numeric > substr(v_pick, 9)::numeric)
         or (split_part(p_selection, '.', 2) = 'UNDER'
             and substr(p_selection, 10)::numeric < substr(v_pick, 10)::numeric) then
        return v_pick;
      end if;
    elsif v_sel_fam = 'BTTS' and split_part(v_pick, '.', 1) = 'BTTS' and p_selection <> v_pick then
      return v_pick;
    end if;
  end loop;
  return null;
end;
$$;

create or replace function app_private.ops_issues()
returns table (key text, code text, severity text, title text, body text, route text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_min integer := app_private.setting_int('ops.api_quota_min_remaining', 750);
  v_http integer := 0;
begin
  -- Synchronisations en échec (2 dernières heures)
  return query
    select 'sync_failed:' || s.job, 'sync_failed', 'warning',
           'Synchronisation « ' || s.job || ' » en échec',
           coalesce(left(max(s.error), 300), 'Erreur sans détail') || ' (' || count(*) || ' échec(s) en 2 h).',
           '/admin/donnees'
    from public.sync_runs s
    where s.status = 'failed' and s.started_at > now() - interval '2 hours'
    group by s.job;

  -- Données qui ne se mettent plus à jour
  if not exists (select 1 from public.sync_runs where job = 'daily' and status in ('success', 'partial')
                 and started_at > now() - interval '26 hours') then
    return query select 'sync_stale:daily', 'sync_stale', 'critical',
      'Calendrier et résultats non mis à jour depuis plus de 26 h',
      'La synchronisation quotidienne n''a pas abouti : matchs, résultats et règlements peuvent être en retard.',
      '/admin/donnees';
  end if;
  if not exists (select 1 from public.sync_runs where job = 'odds' and status in ('success', 'partial')
                 and started_at > now() - interval '13 hours') then
    return query select 'sync_stale:odds', 'sync_stale', 'warning',
      'Cotes non relevées depuis plus de 13 h',
      'Les coupons et analyses s''appuient sur des cotes anciennes.', '/admin/donnees';
  end if;

  -- Quota API-Football
  return query
    select 'api_quota', 'api_quota', 'critical',
           'Quota API-Football presque épuisé',
           'Il reste ' || q.requests_remaining || ' requêtes aujourd''hui (seuil d''alerte : ' || v_min || ').',
           '/admin/donnees'
    from (select s.requests_remaining from public.sync_runs s
          where s.requests_remaining is not null and s.started_at > now() - interval '6 hours'
          order by s.started_at desc limit 1) q
    where q.requests_remaining < v_min;

  -- IA en panne : au moins 3 erreurs et aucun succès en 30 minutes
  return query
    select 'ai_down', 'ai_down', 'critical', 'IA indisponible',
           count(*) filter (where a.status = 'error') || ' erreurs en 30 minutes sans aucune réponse valide. Dernière : '
             || coalesce(left((array_agg(a.error order by a.created_at desc) filter (where a.status = 'error'))[1], 200), '—'),
           '/admin/ia'
    from public.ai_requests a
    where a.created_at > now() - interval '30 minutes' and a.kind <> 'provider_test'
    having count(*) filter (where a.status = 'error') >= 3 and count(*) filter (where a.status = 'success') = 0;

  -- Coupon prêt mais non publié à l'heure
  return query
    select 'coupon_late:' || c.id, 'coupon_late', 'warning',
           'Coupon non publié à l''heure : ' || split_part(c.title, ' · ', 1),
           'Prévu à ' || to_char(c.publish_at at time zone 'Africa/Ouagadougou', 'HH24:MI')
             || ', toujours en attente. Le moteur passe toutes les 15 minutes.',
           '/admin/generations'
    from public.coupons c
    where c.status = 'ready' and c.publish_at < now() - interval '25 minutes' and c.first_kickoff_at > now();

  -- Générations en échec
  return query
    select 'generation_failed', 'generation_failed', 'warning', 'Génération de coupons en échec',
           count(*) || ' génération(s) en échec en 2 h.', '/admin/generations'
    from public.generation_runs g
    where g.status = 'failed' and g.started_at > now() - interval '2 hours'
    having count(*) > 0;

  -- Paiements bloqués
  return query
    select 'payment_stuck', 'payment_stuck', 'warning', 'Paiements en attente depuis plus de 2 h',
           count(*) || ' paiement(s) ni confirmés ni refusés. Vérifiez l''agrégateur.', '/admin/paiements'
    from public.payments p
    where p.status = 'pending' and p.created_at between now() - interval '2 days' and now() - interval '2 hours'
    having count(*) > 0;

  -- Notifications push en échec
  return query
    select 'push_failed', 'push_failed', 'warning', 'Notifications push en échec',
           count(*) || ' notification(s) non envoyées en 1 h (compte Firebase, jetons expirés ?).', null::text
    from public.notifications n
    where n.push_status = 'failed' and n.created_at > now() - interval '1 hour'
    having count(*) >= 10;

  -- Fonctions planifiées en erreur (réponses HTTP de pg_net)
  if to_regclass('net._http_response') is not null then
    execute 'select count(*) from net._http_response where created > now() - interval ''1 hour''
             and (status_code >= 500 or timed_out)' into v_http;
    if v_http >= 3 then
      return query select 'functions_errors', 'functions_errors', 'critical',
        'Fonctions planifiées en erreur',
        v_http || ' appels en erreur ou sans réponse en 1 h (synchronisation, moteur, règlement, notifications).',
        null::text;
    end if;
  end if;

  -- Coupon en circulation qui contredit l'analyse IA d'un de ses matchs
  return query
    select 'coupon_vs_ai:' || c.id, 'coupon_vs_ai', 'warning',
           'Coupon contraire à l''analyse IA : ' || split_part(c.title, ' · ', 1),
           string_agg(distinct h.name || ' – ' || a.name || ' : « ' || app_private.selection_label(s.selection_key, h.name, a.name)
             || ' » contre le pronostic « ' || app_private.selection_label(x.pick, h.name, a.name) || ' »', ' ; ')
             || case c.status when 'published' then '. Coupon publié : retirez-le puis dupliquez-le pour le corriger.'
                              else '. Modifiez-le avant sa publication.' end,
           '/coupon/' || c.id
    from public.coupons c
    join public.coupon_selections s on s.coupon_id = c.id
    join public.matches m on m.id = s.match_id and m.status = 'scheduled'
    join public.teams h on h.id = m.home_team_id
    join public.teams a on a.id = m.away_team_id
    cross join lateral (
      select app_private.ai_contradiction(s.selection_key, ma.analysis) as pick
      from public.match_analyses ma where ma.match_id = s.match_id and ma.status = 'ok'
      order by ma.created_at desc limit 1) x
    where c.status in ('pending_review', 'ready', 'published') and c.first_kickoff_at > now() and not c.ai_override
      and x.pick is not null
    group by c.id, c.title, c.status;

  -- Plantage fréquent dans l'application
  return query
    select 'client_crash:' || e.id, 'client_crash', 'warning',
           'Plantage fréquent dans l''application',
           left(e.message, 200) || ' · ' || e.occurrences || ' fois, ' || cardinality(e.user_ids) || ' utilisateur(s)'
             || coalesce(' · version ' || e.app_version, ''),
           '/admin/sante'
    from public.client_errors e
    where e.kind in ('flutter', 'dart') and e.resolved_at is null and e.last_seen > now() - interval '1 hour'
      and (e.occurrences >= 10 or cardinality(e.user_ids) >= 5);
end;
$$;
revoke all on function app_private.ops_issues() from public, anon, authenticated;
