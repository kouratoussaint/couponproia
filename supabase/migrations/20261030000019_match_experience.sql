-- LOT 9 bis : expérience match et transparence.
--  * Probabilités 1/N/2 selon les cotes (marge retirée) pour la barre des listes de matchs.
--  * Analyse offerte du jour : un match choisi chaque matin, analyse ouverte à tous, sans quota.
--  * match_insights() : classement, comparatif de saison, séries, forme et confrontations,
--    calculés uniquement sur les résultats enregistrés (aucune donnée inventée).

-- -----------------------------------------------------------------------------
-- 1/N/2 selon le marché : probabilité implicite de la cote médiane, marge retirée.
-- -----------------------------------------------------------------------------
create view public.match_1x2_market
with (security_invoker = true) as
with o as (
  select match_id,
         max(odd_median) filter (where outcome_code = 'HOME') as odd_home,
         max(odd_median) filter (where outcome_code = 'DRAW') as odd_draw,
         max(odd_median) filter (where outcome_code = 'AWAY') as odd_away,
         max(bookmakers_count) as bookmakers,
         max(captured_at) as captured_at
  from public.latest_odds
  where market_code = '1X2' and line is null
  group by match_id
)
select match_id, odd_home, odd_draw, odd_away, bookmakers, captured_at,
       round((1 / odd_home) / (1 / odd_home + 1 / odd_draw + 1 / odd_away), 4) as p_home,
       round((1 / odd_draw) / (1 / odd_home + 1 / odd_draw + 1 / odd_away), 4) as p_draw,
       round((1 / odd_away) / (1 / odd_home + 1 / odd_draw + 1 / odd_away), 4) as p_away
from o
where odd_home > 1 and odd_draw > 1 and odd_away > 1;

revoke all on public.match_1x2_market from anon, authenticated;
grant select on public.match_1x2_market to authenticated;

-- -----------------------------------------------------------------------------
-- Analyse offerte du jour
-- -----------------------------------------------------------------------------
create or replace function app_private.local_today()
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (now() at time zone coalesce(
            (select value #>> '{}' from public.app_settings where key = 'app.timezone'), 'UTC'))::date;
$$;

create table public.featured_matches (
  day        date primary key,
  match_id   bigint not null references public.matches(id) on delete cascade,
  chosen_at  timestamptz not null default now()
);

-- Choix stable pour la journée : premier appel → match retenu, appels suivants → le même.
-- Critères : match du jour local, pas encore commencé (plus d'1 h avant), compétition active,
-- cotes 1/N/2 relevées ; priorité de la compétition, puis nombre de bookmakers, puis horaire.
create or replace function public.svc_pick_featured_match(p_day date default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := coalesce(p_day, app_private.local_today());
  v_tz text := coalesce((select value #>> '{}' from public.app_settings where key = 'app.timezone'), 'UTC');
  v_match bigint;
begin
  select match_id into v_match from public.featured_matches where day = v_day;
  if found then
    return v_match;
  end if;
  select m.id into v_match
  from public.matches m
  join public.competitions c on c.id = m.competition_id
  join public.match_1x2_market k on k.match_id = m.id
  where c.is_active
    and m.status = 'scheduled'
    and (m.kickoff_at at time zone v_tz)::date = v_day
    and m.kickoff_at > now() + interval '1 hour'
  order by c.priority, k.bookmakers desc nulls last, m.kickoff_at
  limit 1;
  if v_match is null then
    return null;
  end if;
  insert into public.featured_matches (day, match_id) values (v_day, v_match)
  on conflict (day) do nothing;
  return (select match_id from public.featured_matches where day = v_day);
end;
$$;
revoke all on function public.svc_pick_featured_match(date) from public, anon, authenticated;
grant execute on function public.svc_pick_featured_match(date) to service_role;

-- Match offert du jour (null tant qu'il n'est pas choisi).
create or replace function public.featured_match_today()
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select match_id from public.featured_matches where day = app_private.local_today();
$$;
revoke all on function public.featured_match_today() from public, anon;
grant execute on function public.featured_match_today() to authenticated;
grant execute on function app_private.local_today() to authenticated;

revoke all on public.featured_matches from anon, authenticated;
grant select on public.featured_matches to authenticated;
alter table public.featured_matches enable row level security;
create policy "matchs offerts lisibles" on public.featured_matches for select to authenticated using (true);

insert into public.app_settings (key, value, is_public, description) values
  ('featured.prepare_from_hour', '5'::jsonb, false,
   'Heure locale à partir de laquelle le match offert du jour est choisi et son analyse préparée')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Données de l'onglet Stats d'un match (lecture seule, droits de l'appelant)
-- -----------------------------------------------------------------------------
create or replace function app_private.team_streaks(p_team bigint, p_before timestamptz, p_venue text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r record;
  v_n integer := 0;
  v_total integer;
  -- compteurs : série en cours tant que la condition tient depuis le dernier match
  k text;
  v_keys text[] := array['scored', 'unbeaten', 'wins', 'losses', 'winless', 'clean_sheets', 'conceded'];
  v_len jsonb := '{}'::jsonb;
  v_open jsonb := '{}'::jsonb;
  v_from jsonb := '{}'::jsonb;
  v_to jsonb := '{}'::jsonb;
  v_ok boolean;
  v_out jsonb := '[]'::jsonb;
begin
  foreach k in array v_keys loop
    v_len := v_len || jsonb_build_object(k, 0);
    v_open := v_open || jsonb_build_object(k, true);
  end loop;
  select count(*) into v_total from (
    select 1 from public.matches m
    where m.status in ('finished', 'awarded') and m.home_goals is not null and m.kickoff_at < p_before
      and ((p_venue is null and (m.home_team_id = p_team or m.away_team_id = p_team))
        or (p_venue = 'home' and m.home_team_id = p_team)
        or (p_venue = 'away' and m.away_team_id = p_team))
    order by m.kickoff_at desc limit 40) x;
  for r in
    select m.kickoff_at,
           case when m.home_team_id = p_team then m.home_goals else m.away_goals end as gf,
           case when m.home_team_id = p_team then m.away_goals else m.home_goals end as ga
    from public.matches m
    where m.status in ('finished', 'awarded') and m.home_goals is not null and m.kickoff_at < p_before
      and ((p_venue is null and (m.home_team_id = p_team or m.away_team_id = p_team))
        or (p_venue = 'home' and m.home_team_id = p_team)
        or (p_venue = 'away' and m.away_team_id = p_team))
    order by m.kickoff_at desc
    limit 40
  loop
    v_n := v_n + 1;
    foreach k in array v_keys loop
      if (v_open ->> k)::boolean then
        v_ok := case k
          when 'scored' then r.gf > 0
          when 'unbeaten' then r.gf >= r.ga
          when 'wins' then r.gf > r.ga
          when 'losses' then r.gf < r.ga
          when 'winless' then r.gf <= r.ga
          when 'clean_sheets' then r.ga = 0
          when 'conceded' then r.ga > 0
        end;
        if v_ok then
          v_len := jsonb_set(v_len, array[k], to_jsonb((v_len ->> k)::integer + 1));
          v_from := v_from || jsonb_build_object(k, r.kickoff_at);
          if v_to -> k is null then
            v_to := v_to || jsonb_build_object(k, r.kickoff_at);
          end if;
        else
          v_open := jsonb_set(v_open, array[k], 'false'::jsonb);
        end if;
      end if;
    end loop;
  end loop;
  foreach k in array v_keys loop
    if (v_len ->> k)::integer >= 3 then
      v_out := v_out || jsonb_build_object(
        'key', k,
        'length', (v_len ->> k)::integer,
        -- La série couvre tous les matchs disponibles : elle peut être plus longue.
        'at_least', (v_len ->> k)::integer = v_total,
        'from', v_from -> k,
        'to', v_to -> k);
    end if;
  end loop;
  return v_out;
end;
$$;
revoke all on function app_private.team_streaks(bigint, timestamptz, text) from public, anon;
grant execute on function app_private.team_streaks(bigint, timestamptz, text) to authenticated;

create or replace function public.match_insights(p_match bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  m record;
  v_group text;
begin
  select x.id, x.competition_id, x.season, x.kickoff_at, x.home_team_id, x.away_team_id
    into m from public.matches x where x.id = p_match;
  if not found then
    return null;
  end if;
  select s.group_name into v_group from public.standings s
  where s.competition_id = m.competition_id and s.season = m.season and s.team_id = m.home_team_id
  limit 1;

  return jsonb_build_object(
    'match_id', m.id,
    'computed_at', now(),
    'standings', (
      select jsonb_build_object(
        'updated_at', max(s.updated_at),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
          'rank', s.rank, 'team_id', s.team_id, 'name', t.name, 'logo_url', t.logo_url,
          'played', s.played, 'goal_diff', s.goal_diff, 'points', s.points,
          'form', s.form, 'description', s.description) order by s.rank), '[]'::jsonb))
      from public.standings s join public.teams t on t.id = s.team_id
      where s.competition_id = m.competition_id and s.season = m.season
        and s.group_name = coalesce(v_group, s.group_name)),
    'form', jsonb_build_object(
      'home', app_private.team_form(m.home_team_id, m.kickoff_at, null),
      'away', app_private.team_form(m.away_team_id, m.kickoff_at, null),
      'home_at_home', app_private.team_form(m.home_team_id, m.kickoff_at, 'home'),
      'away_away', app_private.team_form(m.away_team_id, m.kickoff_at, 'away')),
    'season', jsonb_build_object(
      'home', app_private.team_season(m.home_team_id, m.competition_id, m.season, m.kickoff_at),
      'away', app_private.team_season(m.away_team_id, m.competition_id, m.season, m.kickoff_at)),
    'streaks', jsonb_build_object(
      'home', app_private.team_streaks(m.home_team_id, m.kickoff_at, null),
      'away', app_private.team_streaks(m.away_team_id, m.kickoff_at, null),
      'home_at_home', app_private.team_streaks(m.home_team_id, m.kickoff_at, 'home'),
      'away_away', app_private.team_streaks(m.away_team_id, m.kickoff_at, 'away')),
    'h2h', (
      with h as (
        select x.kickoff_at, x.home_team_id, x.home_goals, x.away_goals, th.name as home_name, ta.name as away_name,
               c.name as competition
        from public.matches x
        join public.teams th on th.id = x.home_team_id
        join public.teams ta on ta.id = x.away_team_id
        join public.competitions c on c.id = x.competition_id
        where x.status in ('finished', 'awarded') and x.home_goals is not null and x.kickoff_at < m.kickoff_at
          and ((x.home_team_id = m.home_team_id and x.away_team_id = m.away_team_id)
            or (x.home_team_id = m.away_team_id and x.away_team_id = m.home_team_id))
        order by x.kickoff_at desc
        limit 10
      )
      select jsonb_build_object(
        'count', count(*),
        'home_wins', count(*) filter (where (h.home_team_id = m.home_team_id and h.home_goals > h.away_goals)
                                         or (h.home_team_id = m.away_team_id and h.away_goals > h.home_goals)),
        'draws', count(*) filter (where h.home_goals = h.away_goals),
        'away_wins', count(*) filter (where (h.home_team_id = m.away_team_id and h.home_goals > h.away_goals)
                                         or (h.home_team_id = m.home_team_id and h.away_goals > h.home_goals)),
        'avg_goals', round(avg(h.home_goals + h.away_goals), 2),
        'first', min(h.kickoff_at),
        'last', max(h.kickoff_at),
        'matches', coalesce(jsonb_agg(jsonb_build_object(
          'kickoff_at', h.kickoff_at, 'home', h.home_name, 'away', h.away_name,
          'home_goals', h.home_goals, 'away_goals', h.away_goals, 'competition', h.competition,
          'home_is_match_home', h.home_team_id = m.home_team_id) order by h.kickoff_at desc), '[]'::jsonb))
      from h));
end;
$$;

-- 5 derniers matchs joués d'une équipe (toutes compétitions, ou à domicile / à l'extérieur).
create or replace function app_private.team_form(p_team bigint, p_before timestamptz, p_venue text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(f order by (f ->> 'kickoff_at') desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'kickoff_at', x.kickoff_at,
      'opponent', case when x.home_team_id = p_team then ta.name else th.name end,
      'at_home', x.home_team_id = p_team,
      'gf', case when x.home_team_id = p_team then x.home_goals else x.away_goals end,
      'ga', case when x.home_team_id = p_team then x.away_goals else x.home_goals end,
      'result', case
        when x.home_goals = x.away_goals then 'D'
        when (x.home_team_id = p_team) = (x.home_goals > x.away_goals) then 'W'
        else 'L' end,
      'competition', c.name) as f
    from public.matches x
    join public.teams th on th.id = x.home_team_id
    join public.teams ta on ta.id = x.away_team_id
    join public.competitions c on c.id = x.competition_id
    where x.status in ('finished', 'awarded') and x.home_goals is not null and x.kickoff_at < p_before
      and ((p_venue is null and (x.home_team_id = p_team or x.away_team_id = p_team))
        or (p_venue = 'home' and x.home_team_id = p_team)
        or (p_venue = 'away' and x.away_team_id = p_team))
    order by x.kickoff_at desc
    limit 5) t;
$$;

-- Comparatif de saison dans la compétition du match, avant le coup d'envoi.
create or replace function app_private.team_season(p_team bigint, p_competition bigint, p_season integer, p_before timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with g as (
    select case when x.home_team_id = p_team then x.home_goals else x.away_goals end as gf,
           case when x.home_team_id = p_team then x.away_goals else x.home_goals end as ga
    from public.matches x
    where x.competition_id = p_competition and x.season = p_season
      and x.status in ('finished', 'awarded') and x.home_goals is not null and x.kickoff_at < p_before
      and (x.home_team_id = p_team or x.away_team_id = p_team)
  )
  select jsonb_build_object(
    'played', count(*),
    'goals_for', coalesce(sum(gf), 0),
    'goals_against', coalesce(sum(ga), 0),
    'clean_sheets', count(*) filter (where ga = 0),
    'three_plus', count(*) filter (where gf + ga >= 3),
    'btts', count(*) filter (where gf > 0 and ga > 0))
  from g;
$$;

revoke all on function app_private.team_form(bigint, timestamptz, text) from public, anon;
revoke all on function app_private.team_season(bigint, bigint, integer, timestamptz) from public, anon;
grant execute on function app_private.team_form(bigint, timestamptz, text) to authenticated;
grant execute on function app_private.team_season(bigint, bigint, integer, timestamptz) to authenticated;
revoke all on function public.match_insights(bigint) from public, anon;
grant execute on function public.match_insights(bigint) to authenticated;
