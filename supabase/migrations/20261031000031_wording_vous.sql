-- Vouvoiement partout : textes des notifications envoyées par le serveur.
-- (Corrections validées le 31/10 : un seul registre, « vous », dans toute l'application.)

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
      'Il vous reste ' || (new.plan_credits + new.extra_credits) || ' crédit. Votre forfait se recharge chaque mois ; des packs sont disponibles.',
      '/abonnement', 'credits:' || to_char(now(), 'YYYY-MM-DD'));
  end if;
  return new;
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
      '/accueil', 'morning:' || v_day);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
