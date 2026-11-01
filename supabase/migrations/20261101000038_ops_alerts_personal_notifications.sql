-- LOT 17 (01/11) : alertes personnalisées (B3), suivi des plantages et lenteurs (C3),
-- alertes d'exploitation pour le super administrateur (C4). Le mode hors connexion (C1) est
-- entièrement côté application.

-- -----------------------------------------------------------------------------
-- Permission « santé de l'application » (super administrateur)
-- -----------------------------------------------------------------------------
insert into public.permissions (id, description) values
  ('ops.monitor', 'Voir les alertes d''exploitation et les plantages de l''application, recevoir les alertes')
on conflict (id) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id) values ('super_admin', 'ops.monitor')
on conflict do nothing;

insert into public.app_settings (key, value, is_public, description) values
  ('ops.api_quota_min_remaining', '750'::jsonb, false,
   'Alerte d''exploitation quand il reste moins de ce nombre de requêtes API-Football dans la journée'),
  ('ops.email_enabled', 'true'::jsonb, false,
   'Alertes d''exploitation : envoyer aussi un e-mail au super administrateur (SMTP requis)')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- B3. Alertes personnalisées : préférences
-- -----------------------------------------------------------------------------
alter table public.user_preferences
  add column coupon_categories text[] not null default '{}'
    check (coupon_categories <@ array['du_jour', 'prudent', 'equilibre', 'audacieux', 'cote_elevee',
                                     'multi_competitions', 'competition', 'marche', 'strategie']::text[]),
  add column notify_analyses boolean not null default true,
  add column notify_bet_reminders boolean not null default true,
  add column notify_live boolean not null default true;
comment on column public.user_preferences.coupon_categories is
  'Types de coupons notifiés à la publication ; vide = tous ceux que le forfait permet de lire';
grant update (coupon_categories, notify_analyses, notify_bet_reminders, notify_live)
  on public.user_preferences to authenticated;

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('coupon', 'result', 'tipster', 'match', 'morning', 'credits', 'system', 'odds', 'budget',
                  'analysis', 'reminder', 'live'));

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
        when 'analysis' then v_prefs.notify_analyses
        when 'reminder' then v_prefs.notify_bet_reminders
        when 'live' then v_prefs.notify_live
        else true end;  -- budget, system : toujours (jeu responsable, exploitation)
  if not coalesce(v_wanted, true) then
    return;
  end if;
  insert into public.notifications (user_id, kind, title, body, route, dedupe_key, push_status, send_after)
  values (p_user, p_kind, left(p_title, 120), left(p_body, 400), p_route, p_dedupe,
          case when coalesce(v_prefs.notifications_enabled, true) and app_private.flag_on('notifications')
               then 'pending' else 'disabled' end,
          -- Budget, exploitation et scores en direct : utiles tout de suite ou jamais.
          case when p_kind in ('budget', 'system', 'live', 'reminder') then now() else app_private.quiet_until(p_user) end)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;
revoke all on function app_private.notify(uuid, text, text, text, text, text) from public, anon, authenticated;

-- Coupon publié : seulement aux utilisateurs intéressés par ce type (vide = tous).
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
      and (cardinality(up.coupon_categories) = 0 or new.category = any(up.coupon_categories))
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
revoke all on function app_private.on_coupon_published() from public, anon, authenticated;

-- Équipe suivie analysée : la fiche du match est prête (une fois par match).
create or replace function app_private.on_match_analysed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_home text;
  v_away text;
  v_kickoff timestamptz;
begin
  select h.name, a.name, m.kickoff_at into v_home, v_away, v_kickoff
  from public.matches m join public.teams h on h.id = m.home_team_id join public.teams a on a.id = m.away_team_id
  where m.id = new.match_id and m.status = 'scheduled' and m.kickoff_at > now();
  if not found then
    return new;
  end if;
  for r in
    select distinct f.user_id, t.name as team
    from public.matches m
    join public.user_favorites f on f.team_id in (m.home_team_id, m.away_team_id)
    join public.teams t on t.id = f.team_id
    join public.profiles p on p.id = f.user_id and not p.is_suspended
    where m.id = new.match_id
  loop
    perform app_private.notify(r.user_id, 'analysis', 'Analyse prête : ' || v_home || ' – ' || v_away,
      r.team || ', votre équipe suivie, joue le ' || to_char(v_kickoff at time zone 'Africa/Ouagadougou', 'DD/MM à HH24:MI')
      || '. Probabilités, forme et cotes : la fiche du match est à jour.',
      '/match/' || new.match_id, 'analysis:' || new.match_id);
  end loop;
  return new;
end;
$$;
create trigger match_analyses_notify after insert on public.match_analyses
  for each row execute function app_private.on_match_analysed();
revoke all on function app_private.on_match_analysed() from public, anon, authenticated;

-- Rappel 15 minutes avant le premier match d'un pari noté dans le carnet (toutes les 5 minutes).
create or replace function app_private.notify_bet_reminders()
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
    select j.id, j.user_id, j.title, j.stake, j.total_odd, j.first_kickoff_at
    from public.bet_journal j
    where j.result is null
      and j.first_kickoff_at between now() + interval '10 minutes' and now() + interval '20 minutes'
  loop
    perform app_private.notify(r.user_id, 'reminder', 'Votre pari commence bientôt',
      r.title || ' : coup d''envoi à ' || to_char(r.first_kickoff_at at time zone 'Africa/Ouagadougou', 'HH24:MI')
      || ' (mise ' || app_private.fcfa(r.stake) || ', cote ' || replace(to_char(r.total_odd, 'FM99990.00'), '.', ',') || ').',
      '/carnet', 'reminder:' || r.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function app_private.notify_bet_reminders() from public, anon, authenticated;

-- Issue d'une sélection au score courant : vrai si elle passerait, faux sinon, null si indécidable.
create or replace function app_private.outcome_at(p_key text, p_home integer, p_away integer)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case split_part(p_key, '.', 1)
    when '1X2' then case split_part(p_key, '.', 2) when 'HOME' then p_home > p_away
                                                   when 'AWAY' then p_away > p_home else p_home = p_away end
    when 'DC' then case split_part(p_key, '.', 2) when '1X' then p_home >= p_away
                                                  when 'X2' then p_away >= p_home else p_home <> p_away end
    when 'OU' then case split_part(p_key, '.', 2)
                     when 'OVER' then p_home + p_away > substr(p_key, 9)::numeric
                     else p_home + p_away < substr(p_key, 10)::numeric end
    when 'BTTS' then case split_part(p_key, '.', 2) when 'YES' then p_home > 0 and p_away > 0
                                                    else p_home = 0 or p_away = 0 end
    end;
$$;

create index bet_journal_legs_idx on public.bet_journal using gin (legs jsonb_path_ops) where result is null;

-- But en direct : aux utilisateurs dont un pari du carnet (non réglé) ou un coupon suivi porte sur ce
-- match. Une notification par utilisateur et par score.
create or replace function app_private.on_live_goal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_home text;
  v_away text;
  v_score text;
begin
  if new.status <> 'live' or new.home_goals is null or new.away_goals is null then
    return new;
  end if;
  select h.name, a.name into v_home, v_away from public.teams h, public.teams a
  where h.id = new.home_team_id and a.id = new.away_team_id;
  v_score := v_home || ' ' || new.home_goals || '–' || new.away_goals || ' ' || v_away;
  for r in
    with picks as (
      select j.user_id, l ->> 'key' as key
      from public.bet_journal j cross join lateral jsonb_array_elements(j.legs) l
      where j.result is null and j.legs @> jsonb_build_array(jsonb_build_object('match_id', new.id))
        and (l ->> 'match_id')::bigint = new.id
      union
      select w.user_id, s.selection_key
      from public.coupon_watches w
      join public.coupons c on c.id = w.coupon_id and c.status = 'published' and c.result is null
      join public.coupon_selections s on s.coupon_id = c.id and s.match_id = new.id
    )
    select user_id,
           string_agg(distinct app_private.selection_label(key, v_home, v_away) || ' : '
             || case app_private.outcome_at(key, new.home_goals, new.away_goals)
                  when true then 'en bonne voie' when false then 'compromis à ce score' else 'à suivre' end, ' · ') as status
    from picks group by user_id
  loop
    perform app_private.notify(r.user_id, 'live',
      case when coalesce(old.home_goals, 0) + coalesce(old.away_goals, 0) < new.home_goals + new.away_goals
           then 'But ! ' else 'Score corrigé : ' end || v_score,
      r.status || '. Score en direct, provisoire jusqu''au coup de sifflet final.',
      '/match/' || new.id, 'live:' || new.id || ':' || new.home_goals || '-' || new.away_goals);
  end loop;
  return new;
end;
$$;
create trigger matches_notify_goal after update of home_goals, away_goals on public.matches
  for each row when (old.home_goals is distinct from new.home_goals or old.away_goals is distinct from new.away_goals)
  execute function app_private.on_live_goal();
revoke all on function app_private.on_live_goal() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- C3. Plantages et lenteurs remontés par l'application (sans donnée personnelle)
-- -----------------------------------------------------------------------------
create table public.client_errors (
  id           bigint generated always as identity primary key,
  fingerprint  text not null unique,
  kind         text not null check (kind in ('flutter', 'dart', 'slow')),
  message      text not null check (char_length(message) <= 500),
  stack        text check (char_length(stack) <= 4000),
  context      text check (char_length(context) <= 200),
  app_version  text check (char_length(app_version) <= 40),
  build        integer,
  os           text check (char_length(os) <= 120),
  occurrences  integer not null default 1,
  user_ids     uuid[] not null default '{}',
  first_seen   timestamptz not null default now(),
  last_seen    timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references auth.users(id) on delete set null
);
create index client_errors_last_seen_idx on public.client_errors (last_seen desc);
create index client_errors_resolved_by_idx on public.client_errors (resolved_by);
comment on table public.client_errors is 'Plantages et lenteurs de l''application, regroupés par empreinte (aucun contenu personnel)';

create table public.client_error_reports (
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index client_error_reports_user_idx on public.client_error_reports (user_id, created_at);

revoke all on public.client_errors, public.client_error_reports from anon, authenticated;
grant select on public.client_errors to authenticated;
alter table public.client_errors enable row level security;
alter table public.client_error_reports enable row level security;
create policy "santé : plantages" on public.client_errors for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'ops.monitor'));

create or replace function public.report_client_error(p_kind text, p_message text, p_stack text, p_context text,
                                                      p_version text, p_build integer, p_os text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_msg text := left(btrim(coalesce(p_message, '')), 500);
  v_stack text := left(p_stack, 4000);
  v_top text;
  v_fp text;
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if p_kind not in ('flutter', 'dart', 'slow') or v_msg = '' then
    raise exception 'Rapport invalide' using errcode = '22023';
  end if;
  if (select count(*) from public.client_error_reports where user_id = v_user and created_at > now() - interval '1 hour') >= 30 then
    return;  -- trop de rapports : ignorés en silence
  end if;
  insert into public.client_error_reports (user_id) values (v_user);
  -- Empreinte : type, message sans chiffres, trois premières lignes de la pile (ou le contexte d'une lenteur).
  v_top := coalesce((select string_agg(x, '|') from (
             select regexp_replace(l, '\s+', ' ', 'g') as x
             from unnest(string_to_array(coalesce(v_stack, ''), E'\n')) with ordinality as t(l, n)
             where btrim(l) <> '' order by n limit 3) s), '');
  v_fp := md5(p_kind || '|' || regexp_replace(split_part(v_msg, E'\n', 1), '[0-9]+', '#', 'g') || '|'
              || case when p_kind = 'slow' then coalesce(p_context, '') else v_top end);
  insert into public.client_errors as e (fingerprint, kind, message, stack, context, app_version, build, os, user_ids)
  values (v_fp, p_kind, v_msg, v_stack, left(p_context, 200), left(p_version, 40), p_build, left(p_os, 120), array[v_user])
  on conflict (fingerprint) do update
    set occurrences = e.occurrences + 1,
        last_seen = now(),
        message = excluded.message,
        stack = coalesce(excluded.stack, e.stack),
        context = coalesce(excluded.context, e.context),
        app_version = coalesce(excluded.app_version, e.app_version),
        build = greatest(coalesce(excluded.build, 0), coalesce(e.build, 0)),
        os = coalesce(excluded.os, e.os),
        user_ids = case when v_user = any(e.user_ids) or cardinality(e.user_ids) >= 200 then e.user_ids
                        else e.user_ids || v_user end,
        resolved_at = null, resolved_by = null;  -- revient après correction : rouvert
end;
$$;
revoke all on function public.report_client_error(text, text, text, text, text, integer, text) from public, anon;
grant execute on function public.report_client_error(text, text, text, text, text, integer, text) to authenticated;

create or replace function public.admin_resolve_client_error(p_id bigint, p_resolved boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'ops.monitor') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  update public.client_errors
     set resolved_at = case when p_resolved then now() end,
         resolved_by = case when p_resolved then auth.uid() end
   where id = p_id;
end;
$$;
revoke all on function public.admin_resolve_client_error(bigint, boolean) from public, anon;
grant execute on function public.admin_resolve_client_error(bigint, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- C4. Alertes d'exploitation
-- -----------------------------------------------------------------------------
create table public.ops_alerts (
  id            bigint generated always as identity primary key,
  key           text not null check (char_length(key) <= 120),
  code          text not null,
  severity      text not null check (severity in ('warning', 'critical')),
  title         text not null check (char_length(title) <= 160),
  body          text not null check (char_length(body) <= 600),
  route         text,
  opened_at     timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  resolved_at   timestamptz,
  emailed_at    timestamptz
);
create unique index ops_alerts_open_key on public.ops_alerts (key) where resolved_at is null;
create index ops_alerts_opened_idx on public.ops_alerts (opened_at desc);
revoke all on public.ops_alerts from anon, authenticated;
grant select on public.ops_alerts to authenticated;
alter table public.ops_alerts enable row level security;
create policy "santé : alertes" on public.ops_alerts for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'ops.monitor'));

-- Problèmes constatés maintenant (lecture seule). Chaque ligne : clé stable, gravité, texte.
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

-- Contrôle complet (toutes les 15 minutes, via la fonction ops-monitor) : ouvre, met à jour et
-- clôt les alertes, prévient les super administrateurs. Renvoie les alertes ouvertes à l'instant.
create or replace function public.ops_run_scan()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_id bigint;
  v_opened jsonb := '[]'::jsonb;
  v_resolved integer;
  v_admin record;
begin
  create temporary table if not exists pg_temp.ops_now on commit drop as
    select * from app_private.ops_issues() limit 0;
  truncate pg_temp.ops_now;
  insert into pg_temp.ops_now select * from app_private.ops_issues();

  for r in select * from pg_temp.ops_now loop
    update public.ops_alerts a set last_seen_at = now(), body = left(r.body, 600), severity = r.severity
     where a.key = r.key and a.resolved_at is null
    returning a.id into v_id;
    if not found then
      insert into public.ops_alerts (key, code, severity, title, body, route)
      values (r.key, r.code, r.severity, left(r.title, 160), left(r.body, 600), r.route)
      returning id into v_id;
      v_opened := v_opened || jsonb_build_object('id', v_id, 'severity', r.severity, 'title', r.title, 'body', r.body);
      for v_admin in
        select distinct ur.user_id from public.user_roles ur
        join public.role_permissions rp on rp.role_id = ur.role_id and rp.permission_id = 'ops.monitor'
      loop
        perform app_private.notify(v_admin.user_id, 'system',
          case r.severity when 'critical' then 'Alerte : ' else 'À surveiller : ' end || r.title,
          r.body, '/admin/sante', 'ops:' || v_id);
      end loop;
    end if;
  end loop;

  update public.ops_alerts a set resolved_at = now()
   where a.resolved_at is null and not exists (select 1 from pg_temp.ops_now n where n.key = a.key);
  get diagnostics v_resolved = row_count;

  -- Ménage
  delete from public.client_error_reports where created_at < now() - interval '2 days';
  delete from public.ops_alerts where resolved_at < now() - interval '60 days';

  return jsonb_build_object('opened', v_opened, 'resolved', v_resolved,
                            'open', (select count(*) from public.ops_alerts where resolved_at is null));
end;
$$;
revoke all on function public.ops_run_scan() from public, anon, authenticated;
grant execute on function public.ops_run_scan() to service_role;

-- Destinataires des e-mails d'alerte : comptes ayant la permission ops.monitor.
create or replace function public.ops_recipients()
returns table (email text)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct u.email::text from auth.users u
  join public.user_roles ur on ur.user_id = u.id
  join public.role_permissions rp on rp.role_id = ur.role_id and rp.permission_id = 'ops.monitor'
  where u.email is not null;
$$;
revoke all on function public.ops_recipients() from public, anon, authenticated;
grant execute on function public.ops_recipients() to service_role;

create or replace function app_private.invoke_ops_monitor()
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
    raise notice 'Secrets Vault absents : contrôle d''exploitation non lancé';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/ops-monitor',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_ops_monitor() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname) from cron.job where jobname in ('ops-monitor', 'notify-bet-reminders');
    perform cron.schedule('notify-bet-reminders', '*/5 * * * *', 'select app_private.notify_bet_reminders()');
    if exists (select 1 from pg_extension where extname = 'pg_net') then
      perform cron.schedule('ops-monitor', '7,22,37,52 * * * *', 'select app_private.invoke_ops_monitor()');
    end if;
  end if;
end;
$$;
