-- Mini-implémentation des fonctions pgTAP utilisées par supabase/tests,
-- pour exécuter les tests sur un PostgreSQL nu sans installer l'extension.
-- Les fonctions s'exécutent avec les droits de l'appelant (comme pgTAP), afin
-- que les tests de RLS restent significatifs. Usage local uniquement.

create schema tap;
create table tap.results (id serial primary key, passed boolean not null, description text);
create table tap.plan (planned int not null);
grant usage on schema tap to public;
grant select, insert on tap.results, tap.plan to public;
grant usage on sequence tap.results_id_seq to public;

create function public.plan(n int) returns text language plpgsql as $$
begin
  insert into tap.plan values (n);
  return '1..' || n;
end $$;

create function public.ok(passed boolean, description text) returns text language plpgsql as $$
declare v_id int;
begin
  insert into tap.results (passed, description) values (coalesce(passed, false), description) returning id into v_id;
  return case when coalesce(passed, false) then 'ok ' else 'not ok ' end || v_id || ' - ' || description;
end $$;

create function public.is(have anyelement, want anyelement, description text) returns text language plpgsql as $$
begin
  if have is not distinct from want then
    return public.ok(true, description);
  end if;
  return public.ok(false, description || ' (obtenu: ' || coalesce(have::text, 'NULL') || ', attendu: ' || coalesce(want::text, 'NULL') || ')');
end $$;

create function public.lives_ok(code text, description text) returns text language plpgsql as $$
begin
  execute code;
  return public.ok(true, description);
exception when others then
  return public.ok(false, description || ' (erreur ' || sqlstate || ': ' || sqlerrm || ')');
end $$;

create function public.throws_ok(code text, errcode text, errmsg text, description text) returns text language plpgsql as $$
declare v_state text;
begin
  begin
    execute code;
  exception when others then
    v_state := sqlstate;
  end;
  if v_state is null then
    return public.ok(false, description || ' (aucune erreur levée)');
  end if;
  return public.ok(v_state = errcode, description || case when v_state = errcode then '' else ' (code ' || v_state || ' au lieu de ' || errcode || ')' end);
end $$;

create function public.finish() returns setof text language plpgsql as $$
declare
  v_planned int := (select planned from tap.plan limit 1);
  v_run int := (select count(*) from tap.results);
  v_failed int := (select count(*) from tap.results where not passed);
begin
  if v_run <> v_planned then
    return next '# Prévu ' || v_planned || ' tests, exécuté ' || v_run;
  end if;
  return next '# ' || (v_run - v_failed) || '/' || v_run || ' réussis';
  if v_failed > 0 or v_run <> v_planned then
    raise exception 'ÉCHEC : % test(s) en échec', v_failed + abs(v_run - v_planned);
  end if;
end $$;
