-- LOT 12 : durcissement et optimisation, d'après l'audit (conseils Supabase + revue).
--
-- 1. Fonctions internes : le schéma app_private n'est pas exposé par l'API, mais par précaution
--    les fonctions qui modifient des données ou lisent celles d'un autre utilisateur ne sont
--    plus exécutables que par leur propriétaire (appel via des fonctions SECURITY DEFINER).
--    Les fonctions de déclencheur n'ont pas besoin du droit EXECUTE pour se déclencher.
--    Restent ouvertes : celles utilisées par les règles RLS (has_permission, flag_on,
--    blocked_between, can_see_coupon_selections, post_visible, tipster_visible) et celles appelées
--    par des fonctions publiques SECURITY INVOKER (local_today, team_form, team_season, team_streaks…).
-- 2. Les nouvelles fonctions d'app_private ne sont plus exécutables par tous par défaut.
-- 3. Droits de table inutiles (REFERENCES, TRIGGER, TRUNCATE) retirés aux rôles de l'API.
-- 4. Index sur toutes les clés étrangères (suppression de compte, jointures).

do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_private'
      and (p.prorettype = 'trigger'::regtype
           or p.proname in ('refresh_plan_credits', 'credit_summary', 'active_subscription', 'credits_exempt'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end;
$$;

alter default privileges in schema app_private revoke execute on functions from public;

revoke references, trigger, truncate on all tables in schema public from anon, authenticated;

do $$
declare
  r record;
  v_name text;
begin
  for r in
    select c.conrelid::regclass as tbl, cl.relname, c.conkey,
           string_agg(quote_ident(a.attname), ', ' order by k.ord) as cols,
           string_agg(a.attname, '_' order by k.ord) as colnames
    from pg_constraint c
    join pg_class cl on cl.oid = c.conrelid
    join pg_namespace n on n.oid = cl.relnamespace
    cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f' and n.nspname = 'public'
      and not exists (
        select 1 from pg_index i
        where i.indrelid = c.conrelid
          and (string_to_array(i.indkey::text, ' ')::int2[])[1:cardinality(c.conkey)] = c.conkey)
    group by c.conrelid, cl.relname, c.conkey, c.oid
  loop
    v_name := left(r.relname || '_' || r.colnames, 55) || '_fk_idx';
    execute format('create index if not exists %I on %s (%s)', v_name, r.tbl, r.cols);
  end loop;
end;
$$;

-- 5. Anomalie corrigée : la tâche « matchday » (compositions et absents, LOT 11) était refusée
--    par la liste des tâches autorisées ; elle échouait toutes les 10 minutes.
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
  if p_job not in ('daily', 'odds', 'live', 'matchday') then
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
