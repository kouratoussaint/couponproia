-- Tests pgTAP : lots de l'évaluation du moteur (20/11/2026).
begin;
select plan(3);
select ok(not has_table_privilege('authenticated', 'public.engine_evaluation_parts', 'select'), 'lots invisibles pour les utilisateurs');
select ok(not has_table_privilege('anon', 'public.engine_evaluation_parts', 'select'), 'lots invisibles pour les visiteurs');
select throws_ok($$ insert into public.engine_evaluation_parts (run_id, part, parts, engine_version) values (gen_random_uuid(), 0, 0, 'poisson-3.0') $$, '23514', null, 'au moins un lot');
select * from finish();
rollback;
