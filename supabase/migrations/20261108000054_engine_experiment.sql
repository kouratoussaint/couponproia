-- Laboratoire (08/11/2026) : lancement d'une expérience du moteur par la base, comme
-- l'évaluation hebdomadaire. engine-evaluate en mode `experiment` calcule et renvoie des
-- mesures sans rien enregistrer ; la réponse se lit dans net._http_response (id renvoyé).
create or replace function app_private.invoke_engine_experiment(p_experiment text)
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
  if p_experiment is null or p_experiment !~ '^[a-z0-9-]{1,40}$' then
    raise exception 'expérience invalide' using errcode = '22023';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice 'Vault absent : expérience non lancée';
    return null;
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    raise notice 'Secrets Vault absents : expérience non lancée';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/engine-evaluate',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := jsonb_build_object('experiment', p_experiment),
    timeout_milliseconds := 150000
  ) into v_request;
  return v_request;
end;
$$;

revoke all on function app_private.invoke_engine_experiment(text) from public, anon, authenticated;

comment on function app_private.invoke_engine_experiment(text) is
  'Laboratoire : lance une expérience du moteur (aucune écriture) ; réponse dans net._http_response.';
