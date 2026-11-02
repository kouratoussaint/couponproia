-- Direct « temps réel » (02/11) : le suivi des matchs en cours passe de 5 minutes à 30 secondes.
-- La fonction n'est appelée que s'il y a un match en cours (ou commencé depuis moins de
-- `sports.live_lookback_hours` heures et pas encore terminé), et jamais pendant un passage
-- encore en cours : pas d'appel inutile au fournisseur ni d'invocation inutile.

create or replace function app_private.invoke_live_sync()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hours integer := greatest(1, app_private.setting_int('sports.live_lookback_hours', 3));
begin
  if not exists (
    select 1 from public.matches m
    where m.status in ('scheduled', 'live', 'interrupted')
      and m.kickoff_at <= now() and m.kickoff_at >= now() - make_interval(hours => v_hours)
  ) then
    return null;
  end if;
  if exists (
    select 1 from public.sync_runs r
    where r.job = 'live' and r.status = 'running' and r.started_at > now() - interval '50 seconds'
  ) then
    return null;
  end if;
  return app_private.invoke_sports_sync('live');
end;
$$;
revoke all on function app_private.invoke_live_sync() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.unschedule(jobname) from cron.job where jobname = 'sports-live';
    perform cron.schedule('sports-live', '30 seconds', 'select app_private.invoke_live_sync()');
  end if;
end;
$$;
