-- D5 partie 2 (02/11) : textes écrits par le serveur dans la langue du profil (fr ou en).
--  - Notifications : chaque envoi porte le texte français et, si possible, l'anglais ; notify()
--    choisit selon profiles.locale.
--  - Analyses de match : une analyse par langue (colonne language) ; l'accès acquis reste par match.
--  - Coupons de la plateforme : justification anglaise des sélections (le résumé anglais est dans
--    coupons.analysis -> 'en'), écrits à la création, le coupon publié reste immuable.
--  - Documents légaux : traduction anglaise d'information ; la version française fait foi et c'est
--    elle qui est acceptée.
--  - Campagnes : titre et message anglais facultatifs.
--  - Inscription : la langue choisie dans l'app (métadonnée locale) devient celle du profil.

-- -----------------------------------------------------------------------------
-- Outils de langue
-- -----------------------------------------------------------------------------
create or replace function app_private.user_lang(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$ select coalesce((select locale from public.profiles where id = p_user), 'fr'); $$;
revoke all on function app_private.user_lang(uuid) from public, anon, authenticated;

-- Cote affichée : « 1,95 » / « 1.95 ».
create or replace function app_private.odd_txt(p_odd numeric, p_lang text default 'fr')
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_lang = 'en' then to_char(p_odd, 'FM99990.00')
              else replace(to_char(p_odd, 'FM99990.00'), '.', ',') end;
$$;

-- Montant : « 12 500 FCFA » / « 12,500 FCFA ».
create or replace function app_private.fcfa(p_amount numeric, p_lang text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_lang = 'en' then to_char(round(p_amount), 'FM999,999,999,999') || ' FCFA'
              else app_private.fcfa(p_amount) end;
$$;

-- Date et heure (heure de Ouagadougou) : « 02/11 à 18:00 » / « 02/11 at 18:00 ».
create or replace function app_private.at_txt(p_at timestamptz, p_lang text default 'fr')
returns text
language sql
stable
set search_path = ''
as $$
  select to_char(p_at at time zone 'Africa/Ouagadougou',
                 case when p_lang = 'en' then 'DD/MM "at" HH24:MI' else 'DD/MM "à" HH24:MI' end);
$$;

-- Libellé d'une sélection, dans la langue demandée (marchés DNB et buts par équipe compris).
create or replace function app_private.selection_label(p_key text, p_home text, p_away text, p_lang text)
returns text
language sql
immutable
set search_path = ''
as $$
  with k as (
    select split_part(p_key, '.', 1) as market, split_part(p_key, '.', 2) as outcome,
           substr(p_key, length(split_part(p_key, '.', 1)) + length(split_part(p_key, '.', 2)) + 3) as line
  ), l as (
    select market, outcome, case when p_lang = 'en' then line else replace(line, '.', ',') end as line from k
  )
  select case when p_lang = 'en' then
    case market
      when '1X2' then case outcome when 'HOME' then p_home || ' win' when 'AWAY' then p_away || ' win' else 'Draw' end
      when 'DC' then case outcome when '1X' then p_home || ' or draw' when 'X2' then 'Draw or ' || p_away
                                  else p_home || ' or ' || p_away end
      when 'OU' then case outcome when 'OVER' then 'Over ' else 'Under ' end || line || ' goals'
      when 'BTTS' then case outcome when 'YES' then 'Both teams score' else 'At least one team does not score' end
      when 'DNB' then case outcome when 'HOME' then p_home else p_away end || ' (draw no bet)'
      when 'TTH' then p_home || ': ' || case outcome when 'OVER' then 'over ' else 'under ' end || line
                      || case when line = '0.5' then ' goal' else ' goals' end
      when 'TTA' then p_away || ': ' || case outcome when 'OVER' then 'over ' else 'under ' end || line
                      || case when line = '0.5' then ' goal' else ' goals' end
      else p_key end
  else
    case market
      when '1X2' then case outcome when 'HOME' then 'Victoire ' || p_home when 'AWAY' then 'Victoire ' || p_away
                                   else 'Match nul' end
      when 'DC' then case outcome when '1X' then p_home || ' ou nul' when 'X2' then 'Nul ou ' || p_away
                                  else p_home || ' ou ' || p_away end
      when 'OU' then case outcome when 'OVER' then 'Plus de ' else 'Moins de ' end || line || ' buts'
      when 'BTTS' then case outcome when 'YES' then 'Les deux équipes marquent' else 'Au moins une équipe ne marque pas' end
      when 'DNB' then case outcome when 'HOME' then p_home else p_away end || ' (remboursé si nul)'
      when 'TTH' then p_home || ' : ' || case outcome when 'OVER' then 'plus de ' else 'moins de ' end || line
                      || case when line = '0,5' then ' but' else ' buts' end
      when 'TTA' then p_away || ' : ' || case outcome when 'OVER' then 'plus de ' else 'moins de ' end || line
                      || case when line = '0,5' then ' but' else ' buts' end
      else p_key end
  end from l;
$$;

create or replace function app_private.selection_label(p_key text, p_home text, p_away text)
returns text
language sql
immutable
set search_path = ''
as $$ select app_private.selection_label(p_key, p_home, p_away, 'fr'); $$;

-- Titre de coupon en anglais : noms connus, date française (« lundi 2 novembre ») et
-- « 3 sélections » traduits ; un nom choisi par l'utilisateur reste tel quel.
create or replace function app_private.title_en(p_title text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(coalesce(p_title, ''), ' · ');
  v_out text[] := '{}';
  v_part text;
  v_fr text[] := array['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
                       'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
                       'septembre', 'octobre', 'novembre', 'décembre'];
  v_en text[] := array['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
                       'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
                       'September', 'October', 'November', 'December'];
  i integer;
begin
  foreach v_part in array v_parts loop
    v_part := case replace(v_part, '''', '’')
      when 'Coupon du jour' then 'Coupon of the day'
      when 'Prudent' then 'Cautious'
      when 'Équilibré' then 'Balanced'
      when 'Audacieux' then 'Bold'
      when 'Cote élevée' then 'High odd'
      when 'Multi-compétitions' then 'Multi-competition'
      when 'Spécial compétition' then 'Competition special'
      when 'Spécial marché' then 'Market special'
      when 'Stratégie' then 'Strategy'
      when 'Coupon manuel' then 'Manual coupon'
      when 'Version optimisée' then 'Optimised version'
      when 'Coupon de l’assistant' then 'Assistant coupon'
      else v_part end;
    if v_part ~ '^[0-9]+ sélections?$' then
      v_part := regexp_replace(v_part, 'sélection', 'selection');
    elsif v_part ~* '^(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche) [0-9]{1,2} ' then
      for i in 1 .. array_length(v_fr, 1) loop
        v_part := regexp_replace(v_part, '\m' || v_fr[i] || '\M', v_en[i], 'i');
      end loop;
    end if;
    v_out := v_out || v_part;
  end loop;
  return array_to_string(v_out, ' · ');
end;
$$;

-- Mots interdits : aussi en anglais (titres, campagnes, publications).
create or replace function app_private.has_forbidden_words(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_text, '') ~* ('(^|[^[:alnum:]])('
    || 'sûr(e|s|es)?|sûrement|garanti(e|es|s|r|t)?|assuré(e|s|es)?|certitudes?|imparables?|infaillibles?|sans risque|gains?'
    || '|guaranteed?|guarantees|sure (bets?|wins?|thing)|risk[- ]free|winnings|unbeatable|can''?t lose|certaint(y|ies)'
    || ')([^[:alnum:]]|$)')
    or coalesce(p_text, '') ~ '(^|[^[:alnum:]])100 ?%';
$$;

-- -----------------------------------------------------------------------------
-- Notifications : texte anglais facultatif, choisi selon la langue du profil
-- -----------------------------------------------------------------------------
drop function app_private.notify(uuid, text, text, text, text, text);
create or replace function app_private.notify(p_user uuid, p_kind text, p_title text, p_body text,
                                              p_route text default null, p_dedupe text default null,
                                              p_title_en text default null, p_body_en text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prefs public.user_preferences;
  v_wanted boolean;
  v_en boolean := p_title_en is not null and p_body_en is not null and app_private.user_lang(p_user) = 'en';
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
  values (p_user, p_kind, left(case when v_en then p_title_en else p_title end, 120),
          left(case when v_en then p_body_en else p_body end, 400), p_route, p_dedupe,
          case when coalesce(v_prefs.notifications_enabled, true) and app_private.flag_on('notifications')
               then 'pending' else 'disabled' end,
          -- Budget, exploitation et scores en direct : utiles tout de suite ou jamais.
          case when p_kind in ('budget', 'system', 'live', 'reminder') then now() else app_private.quiet_until(p_user) end)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;
revoke all on function app_private.notify(uuid, text, text, text, text, text, text, text) from public, anon, authenticated;

create or replace function app_private.notify_bet_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
  v_time text;
begin
  for r in
    select j.id, j.user_id, j.title, j.stake, j.total_odd, j.first_kickoff_at
    from public.bet_journal j
    where j.result is null
      and j.first_kickoff_at between now() + interval '10 minutes' and now() + interval '20 minutes'
  loop
    v_time := to_char(r.first_kickoff_at at time zone 'Africa/Ouagadougou', 'HH24:MI');
    perform app_private.notify(r.user_id, 'reminder', 'Votre pari commence bientôt',
      r.title || ' : coup d''envoi à ' || v_time
      || ' (mise ' || app_private.fcfa(r.stake) || ', cote ' || app_private.odd_txt(r.total_odd) || ').',
      '/carnet', 'reminder:' || r.id,
      'Your bet starts soon',
      app_private.title_en(r.title) || ': kick-off at ' || v_time
      || ' (stake ' || app_private.fcfa(r.stake, 'en') || ', odd ' || app_private.odd_txt(r.total_odd, 'en') || ').');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function app_private.notify_match_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
  v_time text;
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
    v_time := to_char(r.kickoff_at at time zone 'Africa/Ouagadougou', 'HH24:MI');
    perform app_private.notify(r.user_id, 'match', r.home || ' – ' || r.away || ' à ' || v_time,
      r.competition || ' : coup d''envoi dans 30 minutes. La fiche du match et ses cotes sont à jour.',
      '/match/' || r.id, 'match:' || r.id,
      r.home || ' – ' || r.away || ' at ' || v_time,
      r.competition || ': kick-off in 30 minutes. The match page and its odds are up to date.');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

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
    perform app_private.notify(r.user_id, 'morning', 'Votre rendez-vous du matin',
      v_matches || ' match' || case when v_matches > 1 then 's' else '' end || ' aujourd''hui'
      || coalesce(' · analyse offerte : ' || v_featured, '')
      || coalesce(' · ' || v_coupon || ' publié', '') || '.',
      '/accueil', 'morning:' || v_day,
      'Your morning briefing',
      v_matches || ' match' || case when v_matches > 1 then 'es' else '' end || ' today'
      || coalesce(' · free analysis: ' || v_featured, '')
      || coalesce(' · ' || app_private.title_en(v_coupon) || ' published', '') || '.');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function app_private.notify_odds_moves()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_threshold numeric := app_private.setting_int('alerts.odds_move_percent', 10) / 100.0;
  v_count integer := 0;
  v_down boolean;
  v_pct text;
begin
  for r in
    select w.user_id, c.id as coupon_id, c.title, s.id as selection_id, s.selection_key, s.odd as published,
           lo.odd_median as current, h.name as home, a.name as away
    from public.coupon_watches w
    join public.coupons c on c.id = w.coupon_id and c.status = 'published' and c.first_kickoff_at > now()
    join public.coupon_selections s on s.coupon_id = c.id
    join public.matches m on m.id = s.match_id and m.status = 'scheduled' and m.kickoff_at > now() + interval '10 minutes'
    join public.teams h on h.id = m.home_team_id
    join public.teams a on a.id = m.away_team_id
    join public.latest_odds lo on lo.match_id = s.match_id and lo.market_code = s.market_code
                               and lo.outcome_code = s.outcome_code and lo.line is not distinct from s.line
    where lo.captured_at > c.published_at
      and abs(lo.odd_median - s.odd) / s.odd >= v_threshold
  loop
    v_down := r.current < r.published;
    v_pct := case when v_down then '−' else '+' end || round(abs(r.current - r.published) / r.published * 100);
    perform app_private.notify(r.user_id, 'odds',
      case when v_down then 'Cote en baisse : ' else 'Cote en hausse : ' end || r.home || ' – ' || r.away,
      app_private.selection_label(r.selection_key, r.home, r.away) || ' : '
        || app_private.odd_txt(r.published) || ' → ' || app_private.odd_txt(r.current)
        || ' (' || v_pct || ' %) depuis la publication de « ' || split_part(r.title, ' · ', 1) || ' ». '
        || case when v_down then 'Le marché y croit davantage : le retour potentiel diminue.'
                else 'Le marché y croit moins (absence, composition ?) : revoyez le coupon avant de jouer.' end,
      '/coupon/' || r.coupon_id,
      'odds:' || r.selection_id || ':' || case when v_down then 'down' else 'up' end,
      case when v_down then 'Odd falling: ' else 'Odd rising: ' end || r.home || ' – ' || r.away,
      app_private.selection_label(r.selection_key, r.home, r.away, 'en') || ': '
        || app_private.odd_txt(r.published, 'en') || ' → ' || app_private.odd_txt(r.current, 'en')
        || ' (' || v_pct || '%) since “' || app_private.title_en(split_part(r.title, ' · ', 1)) || '” was published. '
        || case when v_down then 'The market believes in it more: the potential return goes down.'
                else 'The market believes in it less (absence, line-up?): review the coupon before playing.' end);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

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
    perform app_private.notify(r.user_id, 'billing',
      case v_step when 'j+1' then 'Votre forfait ' || r.plan_code || ' a pris fin'
                  else 'Votre forfait ' || r.plan_code || ' se termine bientôt' end,
      case v_step when 'j+1' then 'Il s''est terminé le ' || app_private.at_txt(r.period_end) || '. Touchez pour le renouveler en un geste.'
                  else 'Fin le ' || app_private.at_txt(r.period_end) || '. Renouvelez en un geste pour garder tous vos coupons et analyses.' end,
      '/abonnement?renouveler=' || r.plan_code || '&periode=' || r.period,
      'renew:' || r.id || ':' || v_step,
      case v_step when 'j+1' then 'Your ' || r.plan_code || ' plan has ended'
                  else 'Your ' || r.plan_code || ' plan ends soon' end,
      case v_step when 'j+1' then 'It ended on ' || app_private.at_txt(r.period_end, 'en') || '. Tap to renew it in one step.'
                  else 'Ends on ' || app_private.at_txt(r.period_end, 'en') || '. Renew in one step to keep all your coupons and analyses.' end);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function app_private.on_coupon_published()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
  v_time text;
  r record;
begin
  if new.status <> 'published' or (tg_op = 'UPDATE' and old.status = 'published') or new.first_kickoff_at <= now() then
    return new;
  end if;
  select count(*) into v_n from public.coupon_selections where coupon_id = new.id;
  if v_n = 0 then
    return new;
  end if;
  v_time := to_char(new.first_kickoff_at at time zone 'Africa/Ouagadougou', 'HH24:MI');
  for r in
    select up.user_id from public.user_preferences up join public.profiles p on p.id = up.user_id
    where up.notify_coupons and not p.is_suspended
      and (cardinality(up.coupon_categories) = 0 or new.category = any(up.coupon_categories))
      and app_private.can_see_coupon(up.user_id, new.category, new.first_kickoff_at, new.last_kickoff_at)
  loop
    perform app_private.notify(r.user_id, 'coupon', 'Nouveau coupon : ' || new.title,
      v_n || ' sélection' || case when v_n > 1 then 's' else '' end || ' · cote ' ||
      app_private.odd_txt(new.total_odd) || ' · premier match à ' || v_time || '. Estimations, sans garantie.',
      '/coupon/' || new.id, 'coupon:' || new.id,
      'New coupon: ' || app_private.title_en(new.title),
      v_n || ' selection' || case when v_n > 1 then 's' else '' end || ' · odd ' ||
      app_private.odd_txt(new.total_odd, 'en') || ' · first match at ' || v_time || '. Estimates, no promise.');
  end loop;
  return new;
end;
$$;

create or replace function app_private.on_credits_low()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer := new.plan_credits + new.extra_credits;
begin
  if old.plan_credits + old.extra_credits > 1 and v_left <= 1
     and not app_private.credits_exempt(new.user_id) then
    perform app_private.notify(new.user_id, 'credits', 'Crédits IA presque épuisés',
      'Il vous reste ' || v_left || ' crédit. Votre forfait se recharge chaque mois ; des packs sont disponibles.',
      '/abonnement', 'credits:' || to_char(now(), 'YYYY-MM-DD'),
      'AI credits almost used up',
      'You have ' || v_left || ' credit left. Your plan recharges every month; packs are available.');
  end if;
  return new;
end;
$$;

create or replace function app_private.on_journal_added()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_budget integer;
  v_tz text := coalesce((select value #>> '{}' from public.app_settings where key = 'app.timezone'), 'UTC');
  v_month text := to_char(now() at time zone v_tz, 'YYYY-MM');
  v_after bigint;
  v_before bigint;
begin
  select monthly_budget into v_budget from public.user_preferences where user_id = new.user_id;
  if v_budget is null then
    return new;
  end if;
  select coalesce(sum(stake), 0) into v_after from public.bet_journal
  where user_id = new.user_id and to_char(placed_at at time zone v_tz, 'YYYY-MM') = v_month;
  v_before := v_after - new.stake;
  if v_after >= v_budget and v_before < v_budget then
    perform app_private.notify(new.user_id, 'budget', 'Budget du mois atteint',
      'Vous avez noté ' || app_private.fcfa(v_after) || ' de mises ce mois-ci pour un budget de '
      || app_private.fcfa(v_budget) || '. Faire une pause est une bonne décision.',
      '/carnet', 'budget:' || v_month || ':100',
      'Monthly budget reached',
      'You have logged ' || app_private.fcfa(v_after, 'en') || ' of stakes this month for a budget of '
      || app_private.fcfa(v_budget, 'en') || '. Taking a break is a good decision.');
  elsif v_after >= v_budget * 0.8 and v_before < v_budget * 0.8 then
    perform app_private.notify(new.user_id, 'budget', '80 % de votre budget du mois',
      'Mises notées ce mois-ci : ' || app_private.fcfa(v_after) || ' sur ' || app_private.fcfa(v_budget) || '.',
      '/carnet', 'budget:' || v_month || ':80',
      '80% of your monthly budget',
      'Stakes logged this month: ' || app_private.fcfa(v_after, 'en') || ' of ' || app_private.fcfa(v_budget, 'en') || '.');
  end if;
  return new;
end;
$$;

create or replace function app_private.on_journal_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.result is null or new.result is not distinct from old.result then
    return new;
  end if;
  perform app_private.notify(new.user_id, 'result',
    case new.result when 'won' then 'Carnet : pari passé' when 'lost' then 'Carnet : pari perdu' else 'Carnet : pari annulé' end,
    new.title || ' · mise ' || app_private.fcfa(new.stake) || case new.result
      when 'won' then ', retour ' || app_private.fcfa(new.stake * coalesce(new.settled_odd, new.total_odd))
      when 'void' then ', mise rendue'
      else '' end || '.',
    '/carnet', 'journal:' || new.id || ':' || new.result,
    case new.result when 'won' then 'Betting log: bet won' when 'lost' then 'Betting log: bet lost' else 'Betting log: bet void' end,
    app_private.title_en(new.title) || ' · stake ' || app_private.fcfa(new.stake, 'en') || case new.result
      when 'won' then ', return ' || app_private.fcfa(new.stake * coalesce(new.settled_odd, new.total_odd), 'en')
      when 'void' then ', stake returned'
      else '' end || '.');
  return new;
end;
$$;

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
  v_goal boolean;
begin
  if new.status <> 'live' or new.home_goals is null or new.away_goals is null then
    return new;
  end if;
  select h.name, a.name into v_home, v_away from public.teams h, public.teams a
  where h.id = new.home_team_id and a.id = new.away_team_id;
  v_score := v_home || ' ' || new.home_goals || '–' || new.away_goals || ' ' || v_away;
  v_goal := coalesce(old.home_goals, 0) + coalesce(old.away_goals, 0) < new.home_goals + new.away_goals;
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
                  when true then 'en bonne voie' when false then 'compromis à ce score' else 'à suivre' end, ' · ') as status,
           string_agg(distinct app_private.selection_label(key, v_home, v_away, 'en') || ': '
             || case app_private.outcome_at(key, new.home_goals, new.away_goals)
                  when true then 'on track' when false then 'at risk at this score' else 'to follow' end, ' · ') as status_en
    from picks group by user_id
  loop
    perform app_private.notify(r.user_id, 'live',
      case when v_goal then 'But ! ' else 'Score corrigé : ' end || v_score,
      r.status || '. Score en direct, provisoire jusqu''au coup de sifflet final.',
      '/match/' || new.id, 'live:' || new.id || ':' || new.home_goals || '-' || new.away_goals,
      case when v_goal then 'Goal! ' else 'Score corrected: ' end || v_score,
      r.status_en || '. Live score, provisional until the final whistle.');
  end loop;
  return new;
end;
$$;

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
  -- Une analyse anglaise d'un match déjà analysé ne renvoie pas d'alerte.
  if coalesce(new.language, 'fr') <> 'fr' then
    return new;
  end if;
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
      r.team || ', votre équipe suivie, joue le ' || app_private.at_txt(v_kickoff)
      || '. Ouvrez la fiche du match : « Analyser » donne accès à l''analyse (forfait, ou crédit avec FREE).',
      '/match/' || new.match_id, 'analysis:' || new.match_id,
      'Analysis ready: ' || v_home || ' – ' || v_away,
      r.team || ', a team you follow, plays on ' || app_private.at_txt(v_kickoff, 'en')
      || '. Open the match page: “Analyse” gives access to the analysis (plan, or credit with FREE).');
  end loop;
  return new;
end;
$$;

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
      '/publication/' || new.id, 'post:' || new.id,
      v_name || case new.kind when 'coupon' then ' published a coupon' else ' published an analysis' end,
      coalesce(left(new.body, 140), 'See the post and its result when the time comes.'));
  end loop;
  return new;
end;
$$;

create or replace function app_private.on_user_coupon_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_odd numeric;
begin
  if old.result is null and new.result is not null and new.status = 'saved' then
    v_odd := coalesce(new.settled_odd, new.total_odd);
    perform app_private.notify(new.user_id, 'result',
      case new.result when 'won' then 'Coupon gagné' when 'lost' then 'Coupon perdu' else 'Coupon annulé' end,
      '« ' || new.title || ' » : ' || case new.result
        when 'won' then 'gagné à la cote ' || app_private.odd_txt(v_odd) || '.'
        when 'lost' then 'perdu. Le détail est dans Mes coupons.'
        else 'annulé (match non joué).' end,
      '/mes-coupons/' || new.id, 'result:' || new.id,
      case new.result when 'won' then 'Coupon won' when 'lost' then 'Coupon lost' else 'Coupon void' end,
      '“' || app_private.title_en(new.title) || '”: ' || case new.result
        when 'won' then 'won at odd ' || app_private.odd_txt(v_odd, 'en') || '.'
        when 'lost' then 'lost. Details are in My coupons.'
        else 'void (match not played).' end);
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Campagnes : titre et message anglais facultatifs
-- -----------------------------------------------------------------------------
alter table public.push_campaigns add column title_en text check (char_length(title_en) between 3 and 80),
  add column body_en text check (char_length(body_en) between 3 and 300);

drop function public.admin_send_campaign(text, text, text, text);
create or replace function public.admin_send_campaign(p_segment text, p_title text, p_body text, p_route text,
                                                      p_title_en text default null, p_body_en text default null)
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
  v_title_en text := nullif(btrim(coalesce(p_title_en, '')), '');
  v_body_en text := nullif(btrim(coalesce(p_body_en, '')), '');
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
  if (v_title_en is null) <> (v_body_en is null) then
    raise exception 'Version anglaise : titre et message, ou aucun des deux' using errcode = '22023';
  end if;
  if v_title_en is not null and (char_length(v_title_en) not between 3 and 80 or char_length(v_body_en) not between 3 and 300) then
    raise exception 'Version anglaise : titre (3 à 80 caractères) et message (3 à 300)' using errcode = '22023';
  end if;
  if app_private.has_forbidden_words(p_title || ' ' || p_body || ' ' || coalesce(v_title_en, '') || ' ' || coalesce(v_body_en, '')) then
    raise exception 'Mot interdit (sûr, garanti, assuré, gain, sans risque, 100 %%, guaranteed, winnings…) : les estimations ne sont jamais des promesses'
      using errcode = '22023';
  end if;
  if p_route not in ('/accueil', '/coupons', '/matchs', '/assistant', '/abonnement', '/carnet', '/performances',
                     '/communaute', '/laboratoire') then
    raise exception 'Destination non autorisée' using errcode = '22023';
  end if;
  if (select count(*) from public.push_campaigns where created_at > now() - interval '24 hours') >= 3 then
    raise exception 'Trois envois par 24 heures au plus, pour ne pas lasser les utilisateurs' using errcode = '54000';
  end if;
  insert into public.push_campaigns (segment, title, body, route, audience, created_by, title_en, body_en)
  values (p_segment, btrim(p_title), btrim(p_body), p_route, 0, v_actor, v_title_en, v_body_en) returning id into v_id;
  for v_user in select * from app_private.segment_users(p_segment) loop
    perform app_private.notify(v_user, 'news', btrim(p_title), btrim(p_body), p_route, 'campaign:' || v_id,
                               v_title_en, v_body_en);
    v_n := v_n + 1;
  end loop;
  update public.push_campaigns set audience = v_n where id = v_id;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'campaign.send', 'push_campaign', v_id::text,
          jsonb_build_object('segment', p_segment, 'title', p_title, 'audience', v_n, 'english', v_title_en is not null));
  return v_n;
end;
$$;
revoke all on function public.admin_send_campaign(text, text, text, text, text, text) from public, anon;
grant execute on function public.admin_send_campaign(text, text, text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Analyses de match par langue ; justification anglaise des sélections de la plateforme
-- -----------------------------------------------------------------------------
alter table public.match_analyses add column language text not null default 'fr' check (language in ('fr', 'en'));
create index match_analyses_language_idx on public.match_analyses (match_id, language, created_at desc);

alter table public.coupon_selections add column justification_en text check (char_length(justification_en) <= 600);

-- -----------------------------------------------------------------------------
-- Inscription : langue de l'app enregistrée sur le profil
-- -----------------------------------------------------------------------------
create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_locale text := case when new.raw_user_meta_data ->> 'locale' = 'en' then 'en' else 'fr' end;
begin
  v_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '');
  if v_name is null or char_length(v_name) < 2 then
    v_name := split_part(coalesce(new.email, ''), '@', 1);
  end if;
  if v_name is null or char_length(v_name) < 2 then
    v_name := 'Utilisateur';
  end if;
  v_name := left(v_name, 40);

  insert into public.profiles (id, display_name, locale) values (new.id, v_name, v_locale);
  insert into public.user_preferences (user_id) values (new.id);
  insert into public.user_roles (user_id, role_id) values (new.id, 'user');
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Documents légaux : traduction anglaise (information ; la version française fait foi)
-- -----------------------------------------------------------------------------
create table public.legal_translations (
  document_id  bigint not null references public.legal_documents(id) on delete cascade,
  language     text not null check (language in ('en')),
  title        text not null check (char_length(title) between 3 and 120),
  body         text not null check (char_length(body) between 50 and 60000),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id) on delete set null,
  primary key (document_id, language)
);
create index legal_translations_updated_by_fk_idx on public.legal_translations (updated_by);
alter table public.legal_translations enable row level security;
revoke all on public.legal_translations from anon, authenticated;
grant select on public.legal_translations to anon, authenticated;
create policy "traductions légales publiques" on public.legal_translations for select to anon, authenticated using (true);

create or replace function public.admin_save_legal_translation(p_document_id bigint, p_title text, p_body text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not app_private.has_permission(v_actor, 'settings.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if not exists (select 1 from public.legal_documents where id = p_document_id) then
    raise exception 'Document inconnu' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 3 and 120 or char_length(btrim(coalesce(p_body, ''))) not between 50 and 60000 then
    raise exception 'Titre (3 à 120 caractères) et texte (50 caractères au moins) obligatoires' using errcode = '22023';
  end if;
  insert into public.legal_translations (document_id, language, title, body, updated_by)
  values (p_document_id, 'en', btrim(p_title), btrim(p_body), v_actor)
  on conflict (document_id, language) do update
    set title = excluded.title, body = excluded.body, updated_at = now(), updated_by = excluded.updated_by;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'legal.translate', 'legal_document', p_document_id::text, jsonb_build_object('language', 'en'));
end;
$$;
revoke all on function public.admin_save_legal_translation(bigint, text, text) from public, anon;
grant execute on function public.admin_save_legal_translation(bigint, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Rapport hebdomadaire : langue du destinataire
-- -----------------------------------------------------------------------------
create or replace function public.svc_weekly_report(p_since timestamptz, p_user uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'platform', (
      select jsonb_build_object(
        'won', count(*) filter (where c.result = 'won'),
        'lost', count(*) filter (where c.result = 'lost'),
        'void', count(*) filter (where c.result = 'void'),
        'avg_won_odd', round(avg(c.settled_odd) filter (where c.result = 'won'), 2))
      from public.coupons c
      where c.settled_at >= p_since and c.status <> 'withdrawn'),
    'recipients', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', u.id,
        'email', u.email,
        'name', coalesce(pr.display_name, ''),
        'locale', coalesce(pr.locale, 'fr'),
        'mine', (
          select jsonb_build_object(
            'won', count(*) filter (where uc.result = 'won'),
            'lost', count(*) filter (where uc.result = 'lost'),
            'void', count(*) filter (where uc.result = 'void'))
          from public.user_coupons uc
          where uc.user_id = u.id and uc.status = 'saved' and uc.settled_at >= p_since),
        'journal', (
          select jsonb_build_object(
            'bets', count(*),
            'won', count(*) filter (where b.result = 'won'),
            'lost', count(*) filter (where b.result = 'lost'),
            'staked', coalesce(sum(b.stake), 0),
            'returned', coalesce(sum(case when b.result = 'won' then round(b.stake * b.settled_odd)
                                          when b.result = 'void' then b.stake else 0 end), 0))
          from public.bet_journal b
          where b.user_id = u.id and b.settled_at >= p_since)
      ) order by u.created_at)
      from auth.users u
      join public.user_preferences up on up.user_id = u.id
      left join public.profiles pr on pr.id = u.id
      where u.email is not null and u.email_confirmed_at is not null
        and (case when p_user is null
                  then up.weekly_email
                       and (up.weekly_email_sent_at is null or up.weekly_email_sent_at < now() - interval '6 days')
                  else u.id = p_user end)
    ), '[]'::jsonb));
$$;
revoke all on function public.svc_weekly_report(timestamptz, uuid) from public, anon, authenticated;
grant execute on function public.svc_weekly_report(timestamptz, uuid) to service_role;
