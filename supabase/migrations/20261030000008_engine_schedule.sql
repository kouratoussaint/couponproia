-- =============================================================================
-- Coupon Pro IA — LOT 3 — Évaluation planifiée du moteur
-- Chaque lundi à 5 h 30 (UTC), le moteur est réévalué sur l'historique : la qualité
-- affichée dans l'app reste à jour quand de nouveaux matchs sont joués.
-- =============================================================================

create or replace function app_private.invoke_engine_evaluation()
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
    raise notice 'Secrets Vault absents : évaluation non lancée';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/engine-evaluate',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  ) into v_request;
  return v_request;
end;
$$;

revoke all on function app_private.invoke_engine_evaluation() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('engine-evaluate-weekly', '30 5 * * 1', 'select app_private.invoke_engine_evaluation()');
  else
    raise notice 'pg_cron ou pg_net absent : évaluation hebdomadaire non planifiée';
  end if;
end;
$$;
