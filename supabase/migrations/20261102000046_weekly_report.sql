-- Rapport hebdomadaire par e-mail (C5, 02/11). Sur demande seulement (désactivé par défaut,
-- réglable dans Notifications) : le lundi matin, votre bilan des 7 derniers jours (Mes coupons,
-- carnet de paris) et celui des coupons de la plateforme, pertes comprises.

alter table public.user_preferences
  add column if not exists weekly_email boolean not null default false,
  add column if not exists weekly_email_sent_at timestamptz;
grant update (weekly_email) on public.user_preferences to authenticated;

-- Données du rapport : destinataires (e-mail confirmé, rapport demandé, pas encore servis depuis
-- 6 jours) et leurs chiffres ; bilan de la plateforme. Réservé au serveur.
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

create or replace function app_private.invoke_weekly_report()
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
    raise notice 'Secrets Vault absents : rapport hebdomadaire non lancé';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/weekly-report',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_weekly_report() from public, anon, authenticated;

-- Le lundi à 7 h 05 (heure de Ouagadougou, UTC).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.unschedule(jobname) from cron.job where jobname = 'weekly-report';
    perform cron.schedule('weekly-report', '5 7 * * 1', 'select app_private.invoke_weekly_report()');
  end if;
end;
$$;
