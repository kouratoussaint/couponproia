-- LOT 11 : jour de match.
--  * Compositions officielles (publiées 20 à 40 min avant le coup d'envoi) et absents annoncés,
--    lus chez API-Football par la tâche « matchday » (toutes les 10 min, rien n'est appelé s'il
--    n'y a rien à vérifier).
--  * Scores en direct suivis toutes les 5 min (au lieu de 15) : la tâche « live » ne fait aucune
--    requête quand aucun match n'est en cours.

create table public.match_lineups (
  match_id     bigint not null references public.matches(id) on delete cascade,
  team_id      bigint not null references public.teams(id) on delete cascade,
  formation    text,
  coach        text,
  start_xi     jsonb not null default '[]'::jsonb,
  substitutes  jsonb not null default '[]'::jsonb,
  fetched_at   timestamptz not null default now(),
  primary key (match_id, team_id)
);

create table public.match_absences (
  id            bigint generated always as identity primary key,
  match_id      bigint not null references public.matches(id) on delete cascade,
  team_id       bigint not null references public.teams(id) on delete cascade,
  player_name   text not null,
  absence_type  text,
  reason        text,
  fetched_at    timestamptz not null default now()
);
create index match_absences_match_idx on public.match_absences (match_id);

alter table public.matches add column absences_checked_at timestamptz;

revoke all on public.match_lineups, public.match_absences from anon, authenticated;
grant select on public.match_lineups, public.match_absences to authenticated;
alter table public.match_lineups  enable row level security;
alter table public.match_absences enable row level security;
create policy "compositions lisibles" on public.match_lineups for select to authenticated using (true);
create policy "absents lisibles" on public.match_absences for select to authenticated using (true);

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname) from cron.job where jobname in ('sports-matchday', 'sports-live');
    perform cron.schedule('sports-matchday', '*/10 * * * *', 'select app_private.invoke_sports_sync(''matchday'')');
    perform cron.schedule('sports-live', '*/5 * * * *', 'select app_private.invoke_sports_sync(''live'')');
  end if;
end;
$$;
