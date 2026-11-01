-- LOT 16 (01/11) : simulateur de mise, carnet de paris, alertes de cote, transparence renforcée.
-- Le simulateur ne place aucun pari : Coupon Pro IA n'est pas un bookmaker. Le carnet est un
-- journal personnel que l'utilisateur tient lui-même (mises déclarées, cote obtenue chez son
-- opérateur) ; il est réglé automatiquement sur le score à 90 minutes, comme les coupons.

-- -----------------------------------------------------------------------------
-- Réglages
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, is_public, description) values
  ('simulator.withholding_percent', '0'::jsonb, true,
   'Simulateur de mise : prélèvement appliqué par les opérateurs sur le bénéfice (en %, 0 à 50 ; 0 = aucun)'),
  ('alerts.odds_move_percent', '10'::jsonb, true,
   'Alerte de cote : variation (en %, 3 à 50) de la cote d''une sélection depuis la publication du coupon')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Jeu responsable : plafond par pari et budget mensuel choisis par l'utilisateur
-- -----------------------------------------------------------------------------
alter table public.user_preferences
  add column stake_limit integer check (stake_limit is null or stake_limit between 100 and 100000000),
  add column monthly_budget integer check (monthly_budget is null or monthly_budget between 100 and 1000000000);
comment on column public.user_preferences.stake_limit is 'Plafond par pari (FCFA) choisi par l''utilisateur ; null = aucun';
comment on column public.user_preferences.monthly_budget is 'Budget mensuel de paris (FCFA) choisi par l''utilisateur ; null = aucun';
grant update (stake_limit, monthly_budget) on public.user_preferences to authenticated;

-- -----------------------------------------------------------------------------
-- Notifications : alertes de cote et de budget
-- -----------------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('coupon', 'result', 'tipster', 'match', 'morning', 'credits', 'system', 'odds', 'budget'));

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
        else true end;  -- budget, system : toujours (jeu responsable, sécurité)
  if not coalesce(v_wanted, true) then
    return;
  end if;
  insert into public.notifications (user_id, kind, title, body, route, dedupe_key, push_status, send_after)
  values (p_user, p_kind, left(p_title, 120), left(p_body, 400), p_route, p_dedupe,
          case when coalesce(v_prefs.notifications_enabled, true) and app_private.flag_on('notifications')
               then 'pending' else 'disabled' end,
          case when p_kind = 'budget' then now() else app_private.quiet_until(p_user) end)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;
revoke all on function app_private.notify(uuid, text, text, text, text, text) from public, anon, authenticated;

-- Libellé français d'une sélection (« Victoire Marseille », « Plus de 2,5 buts »…).
create or replace function app_private.selection_label(p_key text, p_home text, p_away text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case split_part(p_key, '.', 1)
    when '1X2' then case split_part(p_key, '.', 2) when 'HOME' then 'Victoire ' || p_home
                                                   when 'AWAY' then 'Victoire ' || p_away else 'Match nul' end
    when 'DC' then case split_part(p_key, '.', 2) when '1X' then p_home || ' ou nul'
                                                  when 'X2' then 'Nul ou ' || p_away else p_home || ' ou ' || p_away end
    when 'OU' then case split_part(p_key, '.', 2) when 'OVER' then 'Plus de ' else 'Moins de ' end
                   || replace(substr(p_key, length(split_part(p_key, '.', 1)) + length(split_part(p_key, '.', 2)) + 3), '.', ',')
                   || ' buts'
    when 'BTTS' then case split_part(p_key, '.', 2) when 'YES' then 'Les deux équipes marquent'
                                                    else 'Au moins une équipe ne marque pas' end
    else p_key end;
$$;

create or replace function app_private.fcfa(p_amount numeric)
returns text
language sql
immutable
set search_path = ''
as $$ select replace(to_char(round(p_amount), 'FM999G999G999G999'), ',', ' ') || ' FCFA'; $$;

-- -----------------------------------------------------------------------------
-- Carnet de paris (journal personnel)
-- -----------------------------------------------------------------------------
create table public.bet_journal (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  source_type  text not null check (source_type in ('coupon', 'user_coupon', 'match', 'analysis', 'lab')),
  source_id    text check (char_length(source_id) <= 64),
  title        text not null check (char_length(title) between 1 and 120),
  stake        integer not null check (stake between 1 and 100000000),
  total_odd    numeric(12, 2) not null check (total_odd between 1.01 and 1000000),
  legs         jsonb not null check (jsonb_typeof(legs) = 'array' and jsonb_array_length(legs) between 1 and 30),
  note         text check (char_length(note) <= 200),
  placed_at    timestamptz not null default now(),
  first_kickoff_at timestamptz not null,
  result       text check (result in ('won', 'lost', 'void')),
  settled_odd  numeric(12, 2),
  settled_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.bet_journal is 'Carnet de paris : mises déclarées par l''utilisateur (aucun pari réel n''est pris par la plateforme)';
create index bet_journal_user_idx on public.bet_journal (user_id, placed_at desc);
create index bet_journal_unsettled_idx on public.bet_journal (first_kickoff_at) where result is null;
create trigger bet_journal_set_updated_at before update on public.bet_journal
  for each row execute function app_private.set_updated_at();

revoke all on public.bet_journal from anon, authenticated;
grant select, delete on public.bet_journal to authenticated;
alter table public.bet_journal enable row level security;
create policy "son carnet" on public.bet_journal for select to authenticated using (user_id = (select auth.uid()));
create policy "supprimer une ligne de son carnet" on public.bet_journal for delete to authenticated
  using (user_id = (select auth.uid()));

-- Ajout d'un pari au carnet : les sélections sont vérifiées (matchs existants, issues connues).
create or replace function public.journal_add(p_source_type text, p_source_id text, p_title text, p_stake integer,
                                              p_total_odd numeric, p_legs jsonb, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_first timestamptz;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if jsonb_typeof(p_legs) <> 'array' or jsonb_array_length(p_legs) not between 1 and 30 then
    raise exception 'Entre 1 et 30 sélections' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_legs) l
             where jsonb_typeof(l) <> 'object'
                or coalesce(l ->> 'key', '') !~ '^(1X2|DC|OU|BTTS)\.[A-Z0-9]+(\.[0-9]+(\.[0-9]+)?)?$'
                or jsonb_typeof(l -> 'odd') <> 'number' or (l ->> 'odd')::numeric not between 1.01 and 1000
                or jsonb_typeof(l -> 'match_id') <> 'number'
                or not exists (select 1 from public.matches m where m.id = (l ->> 'match_id')::bigint)) then
    raise exception 'Sélection invalide' using errcode = '22023';
  end if;
  if (select count(distinct l ->> 'match_id') from jsonb_array_elements(p_legs) l) <> jsonb_array_length(p_legs) then
    raise exception 'Un seul pari par match' using errcode = '22023';
  end if;
  if (select count(*) from public.bet_journal where user_id = v_user and created_at > now() - interval '1 day') >= 100 then
    raise exception 'Limite de 100 ajouts par jour atteinte' using errcode = '54000';
  end if;
  select min(m.kickoff_at) into v_first
  from jsonb_array_elements(p_legs) l join public.matches m on m.id = (l ->> 'match_id')::bigint;

  insert into public.bet_journal (user_id, source_type, source_id, title, stake, total_odd, legs, note, first_kickoff_at)
  values (v_user, p_source_type, p_source_id, btrim(p_title), p_stake, round(p_total_odd, 2),
          (select jsonb_agg(jsonb_build_object('match_id', (l ->> 'match_id')::bigint, 'key', l ->> 'key',
                                               'odd', round((l ->> 'odd')::numeric, 2),
                                               'label', left(coalesce(l ->> 'label', ''), 120),
                                               'match', left(coalesce(l ->> 'match', ''), 120)))
           from jsonb_array_elements(p_legs) l),
          nullif(btrim(p_note), ''), v_first)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.journal_add(text, text, text, integer, numeric, jsonb, text) from public, anon;
grant execute on function public.journal_add(text, text, text, integer, numeric, jsonb, text) to authenticated;

-- Correction de la mise, de la cote obtenue ou de la note (le règlement est recalculé).
create or replace function public.journal_update(p_id uuid, p_stake integer, p_total_odd numeric, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.bet_journal
     set stake = p_stake, total_odd = round(p_total_odd, 2), note = nullif(btrim(p_note), ''),
         settled_odd = case when result = 'won' and settled_odd is not null and total_odd > 0
                            then round(settled_odd * round(p_total_odd, 2) / total_odd, 2) else settled_odd end
   where id = p_id and user_id = auth.uid();
  if not found then
    raise exception 'Pari introuvable' using errcode = 'P0002';
  end if;
end;
$$;
revoke all on function public.journal_update(uuid, integer, numeric, text) from public, anon;
grant execute on function public.journal_update(uuid, integer, numeric, text) to authenticated;

-- Budget mensuel : alerte à 80 % puis à 100 % (mois civil, fuseau de la plateforme).
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
      '/carnet', 'budget:' || v_month || ':100');
  elsif v_after >= v_budget * 0.8 and v_before < v_budget * 0.8 then
    perform app_private.notify(new.user_id, 'budget', '80 % de votre budget du mois',
      'Mises notées ce mois-ci : ' || app_private.fcfa(v_after) || ' sur ' || app_private.fcfa(v_budget) || '.',
      '/carnet', 'budget:' || v_month || ':80');
  end if;
  return new;
end;
$$;
create trigger bet_journal_budget after insert on public.bet_journal
  for each row execute function app_private.on_journal_added();
revoke all on function app_private.on_journal_added() from public, anon, authenticated;

-- Pari du carnet réglé : notification « Résultats ».
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
    '/carnet', 'journal:' || new.id || ':' || new.result);
  return new;
end;
$$;
create trigger bet_journal_settled after update of result on public.bet_journal
  for each row execute function app_private.on_journal_settled();
revoke all on function app_private.on_journal_settled() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Alertes de cote sur les coupons suivis
-- -----------------------------------------------------------------------------
create table public.coupon_watches (
  user_id    uuid not null references auth.users(id) on delete cascade,
  coupon_id  uuid not null references public.coupons(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, coupon_id)
);
create index coupon_watches_coupon_idx on public.coupon_watches (coupon_id);
revoke all on public.coupon_watches from anon, authenticated;
grant select, delete on public.coupon_watches to authenticated;
alter table public.coupon_watches enable row level security;
create policy "ses coupons suivis" on public.coupon_watches for select to authenticated using (user_id = (select auth.uid()));
create policy "ne plus suivre" on public.coupon_watches for delete to authenticated using (user_id = (select auth.uid()));

create or replace function public.set_coupon_watch(p_coupon uuid, p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if not p_on then
    delete from public.coupon_watches where user_id = v_user and coupon_id = p_coupon;
    return false;
  end if;
  if not exists (select 1 from public.coupons c
                 where c.id = p_coupon and c.status = 'published' and c.first_kickoff_at > now()
                   and app_private.can_see_coupon_selections(v_user, c.category, c.first_kickoff_at)) then
    raise exception 'Coupon non suivable (déjà commencé ou réservé)' using errcode = '22023';
  end if;
  if (select count(*) from public.coupon_watches where user_id = v_user) >= 50 then
    delete from public.coupon_watches w using public.coupons c
    where w.user_id = v_user and c.id = w.coupon_id and c.first_kickoff_at < now();
  end if;
  insert into public.coupon_watches (user_id, coupon_id) values (v_user, p_coupon) on conflict do nothing;
  return true;
end;
$$;
revoke all on function public.set_coupon_watch(uuid, boolean) from public, anon;
grant execute on function public.set_coupon_watch(uuid, boolean) to authenticated;

-- Toutes les 10 minutes : cote d'une sélection d'un coupon suivi qui a bougé d'au moins le seuil
-- réglé depuis la publication. Une alerte par sélection et par sens.
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
    perform app_private.notify(r.user_id, 'odds',
      case when v_down then 'Cote en baisse : ' else 'Cote en hausse : ' end || r.home || ' – ' || r.away,
      app_private.selection_label(r.selection_key, r.home, r.away) || ' : '
        || replace(to_char(r.published, 'FM990.00'), '.', ',') || ' → ' || replace(to_char(r.current, 'FM990.00'), '.', ',')
        || ' (' || case when v_down then '−' else '+' end
        || round(abs(r.current - r.published) / r.published * 100) || ' %) depuis la publication de « '
        || split_part(r.title, ' · ', 1) || ' ». '
        || case when v_down then 'Le marché y croit davantage : le retour potentiel diminue.'
                else 'Le marché y croit moins (absence, composition ?) : revoyez le coupon avant de jouer.' end,
      '/coupon/' || r.coupon_id,
      'odds:' || r.selection_id || ':' || case when v_down then 'down' else 'up' end);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke all on function app_private.notify_odds_moves() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname) from cron.job where jobname = 'notify-odds-moves';
    perform cron.schedule('notify-odds-moves', '3,13,23,33,43,53 * * * *', 'select app_private.notify_odds_moves()');
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Réglages : validation des deux nouvelles valeurs
-- -----------------------------------------------------------------------------
create or replace function public.admin_set_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
begin
  if not app_private.has_permission(auth.uid(), 'settings.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_key like 'ai.%' and not app_private.has_permission(auth.uid(), 'ai.providers') then
    raise exception 'Réglages IA réservés au super administrateur' using errcode = '42501';
  end if;
  select value into v_old from public.app_settings where key = p_key for update;
  if not found then
    raise exception 'Réglage inconnu : %', p_key using errcode = 'P0002';
  end if;
  if p_value is null or (jsonb_typeof(v_old) <> 'null' and jsonb_typeof(p_value) <> 'null'
                         and jsonb_typeof(v_old) <> jsonb_typeof(p_value)) then
    raise exception 'Type attendu : %', jsonb_typeof(v_old) using errcode = '22023';
  end if;
  if p_key = 'pricing.plans' then
    perform app_private.validate_pricing_plans(p_value);
  elsif p_key in ('pricing.annual_discount_percent') and ((p_value #>> '{}')::numeric < 0 or (p_value #>> '{}')::numeric > 90) then
    raise exception 'Remise entre 0 et 90 %%' using errcode = '22023';
  elsif p_key = 'costs.payment_fee_percent' and ((p_value #>> '{}')::numeric < 0 or (p_value #>> '{}')::numeric > 20) then
    raise exception 'Commission entre 0 et 20 %%' using errcode = '22023';
  elsif p_key = 'costs.usd_to_xof' and (p_value #>> '{}')::numeric <= 0 then
    raise exception 'Taux de conversion positif obligatoire' using errcode = '22023';
  elsif p_key = 'costs.fixed_monthly_xof' and exists (
          select 1 from jsonb_each(p_value) e
          where jsonb_typeof(e.value) <> 'number' or (e.value #>> '{}')::numeric < 0 or btrim(e.key) = '') then
    raise exception 'Chaque abonnement : un nom et un montant positif en FCFA' using errcode = '22023';
  elsif p_key = 'legal.editor' and (
          jsonb_typeof(p_value) <> 'object'
          or exists (select 1 from jsonb_each(p_value) e
                     where e.key not in ('name', 'legal_form', 'address', 'country', 'registration')
                        or jsonb_typeof(e.value) <> 'string' or char_length(e.value #>> '{}') > 200)) then
    raise exception 'Éditeur : champs name, legal_form, address, country, registration (texte, 200 caractères maximum)'
      using errcode = '22023';
  elsif p_key = 'app.support_email' and jsonb_typeof(p_value) <> 'null' and (
          jsonb_typeof(p_value) <> 'string'
          or (p_value #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
          or char_length(p_value #>> '{}') > 254) then
    raise exception 'Adresse e-mail du support invalide' using errcode = '22023';
  elsif p_key = 'coupons.market_weight' and ((p_value #>> '{}')::numeric < 0 or (p_value #>> '{}')::numeric > 1) then
    raise exception 'Part du marché entre 0 et 1' using errcode = '22023';
  elsif p_key = 'coupons.max_match_uses' and ((p_value #>> '{}')::numeric not between 0 and 10
                                              or (p_value #>> '{}')::numeric <> round((p_value #>> '{}')::numeric)) then
    raise exception 'Nombre entier entre 0 et 10' using errcode = '22023';
  elsif p_key = 'payments.providers' and (
          jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) = 0
          or exists (select 1 from jsonb_array_elements(p_value) e
                     where jsonb_typeof(e) <> 'string' or (e #>> '{}') not in ('ligdicash', 'cinetpay'))
          or (select count(distinct e #>> '{}') from jsonb_array_elements(p_value) e) <> jsonb_array_length(p_value)) then
    raise exception 'Agrégateurs : liste ordonnée sans doublon parmi ligdicash et cinetpay (au moins un)' using errcode = '22023';
  elsif p_key = 'featured.auto_pick_hour' and (jsonb_typeof(p_value) <> 'number'
          or (p_value #>> '{}')::numeric not between 0 and 23
          or (p_value #>> '{}')::numeric <> round((p_value #>> '{}')::numeric)) then
    raise exception 'Heure entière entre 0 et 23' using errcode = '22023';
  elsif p_key = 'bookmaker.link' and jsonb_typeof(p_value) <> 'null' and (
          jsonb_typeof(p_value) <> 'object'
          or char_length(coalesce(p_value ->> 'name', '')) not between 1 and 40
          or coalesce(p_value ->> 'url', '') !~ '^https://[^\s]+$'
          or char_length(p_value ->> 'url') > 300) then
    raise exception 'Lien du bookmaker : {"name": "…", "url": "https://…"} ou null' using errcode = '22023';
  elsif p_key = 'simulator.withholding_percent' and (jsonb_typeof(p_value) <> 'number'
          or (p_value #>> '{}')::numeric not between 0 and 50) then
    raise exception 'Prélèvement entre 0 et 50 %%' using errcode = '22023';
  elsif p_key = 'alerts.odds_move_percent' and (jsonb_typeof(p_value) <> 'number'
          or (p_value #>> '{}')::numeric not between 3 and 50
          or (p_value #>> '{}')::numeric <> round((p_value #>> '{}')::numeric)) then
    raise exception 'Seuil entier entre 3 et 50 %%' using errcode = '22023';
  elsif jsonb_typeof(p_value) = 'number' and (p_value #>> '{}')::numeric < 0 then
    raise exception 'Valeur négative refusée' using errcode = '22023';
  end if;
  update public.app_settings set value = p_value where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), 'settings.update', 'setting', p_key, jsonb_build_object('old', v_old, 'new', p_value));
end;
$$;

-- -----------------------------------------------------------------------------
-- Performances : coupons réglés et retour cumulé (pour le résultat à mise fixe), par catégorie
-- -----------------------------------------------------------------------------
create or replace function public.platform_performance(p_days integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select c.id, c.category, c.status, c.total_odd, c.result, c.settled_odd, c.published_at, c.first_kickoff_at
    from public.coupons c
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
    'settled', (select count(*) from settled),
    'returned', (select round(coalesce(sum(settled_odd) filter (where result = 'won'), 0), 2) from settled),
    'theoretical_return', (select round((coalesce(sum(settled_odd) filter (where result = 'won'), 0) - count(*)) / nullif(count(*), 0), 4) from settled),
    'by_category', coalesce((
      select jsonb_agg(x order by x->>'key') from (
        select jsonb_build_object('key', category, 'coupons', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost'),
          'win_rate', round(count(*) filter (where result = 'won')::numeric / nullif(count(*) filter (where result in ('won', 'lost')), 0), 4),
          'average_odd', round(avg(total_odd), 2),
          'settled', count(*) filter (where result in ('won', 'lost')),
          'returned', round(coalesce(sum(settled_odd) filter (where result = 'won'), 0), 2)) as x
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
