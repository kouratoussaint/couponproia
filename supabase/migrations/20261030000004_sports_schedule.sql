-- =============================================================================
-- Coupon Pro IA — LOT 2 — Planification des synchronisations
-- pg_cron appelle l'Edge Function sports-sync via pg_net. L'URL du projet et le
-- secret partagé sont lus dans Supabase Vault (écrits par le workflow de
-- déploiement) : rien de secret dans les migrations.
-- =============================================================================

create or replace function app_private.invoke_sports_sync(p_job text)
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
  if p_job not in ('daily', 'odds', 'live') then
    raise exception 'Tâche inconnue : %', p_job using errcode = '22023';
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
    body := jsonb_build_object('job', p_job),
    timeout_milliseconds := 10000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_sports_sync(text) from public, anon, authenticated;

-- Horaires en UTC (= heure de Ouagadougou)
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'pg_cron ou pg_net indisponible : planification ignorée (environnement de test).';
    return;
  end if;
  execute 'create extension if not exists pg_net with schema extensions';
  execute 'create extension if not exists pg_cron';
  -- Saisons, calendriers, résultats et classements : chaque matin
  execute $q$select cron.schedule('sports-daily', '0 4 * * *', 'select app_private.invoke_sports_sync(''daily'')')$q$;
  -- Cotes des matchs des 48 prochaines heures : matin et après-midi
  execute $q$select cron.schedule('sports-odds', '0 7,15 * * *', 'select app_private.invoke_sports_sync(''odds'')')$q$;
  -- Scores en direct : toutes les 15 minutes (aucune requête s'il n'y a pas de match en cours)
  execute $q$select cron.schedule('sports-live', '*/15 * * * *', 'select app_private.invoke_sports_sync(''live'')')$q$;
end;
$$;
