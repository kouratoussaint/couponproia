-- LOT 9 bis (suite) : premier lancement en 3 étapes (pseudo, compétitions suivies, niveau).
-- Les compétitions suivies passent en tête de l'accueil ; le niveau règle les explications
-- affichées dans l'app (définitions des termes pour un débutant). Les chiffres ne changent jamais
-- selon le niveau.
-- La ligne user_preferences existe déjà pour chaque compte (créée à l'inscription, LOT 1).

alter table public.user_preferences
  add column favorite_competitions bigint[] not null default '{}'
    check (cardinality(favorite_competitions) <= 30),
  add column level text check (level in ('debutant', 'intermediaire', 'expert')),
  -- Renseigné quand le parcours est terminé ou passé : il ne s'affiche plus ensuite.
  add column onboarded_at timestamptz;

-- Seules des compétitions existantes peuvent être suivies (sans doublon).
create or replace function app_private.check_user_preferences()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.favorite_competitions := coalesce((select array_agg(distinct c order by c) from unnest(new.favorite_competitions) c), '{}');
  if exists (select 1 from unnest(new.favorite_competitions) c
             where not exists (select 1 from public.competitions k where k.id = c)) then
    raise exception 'Compétition inconnue' using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger user_preferences_check
  before insert or update on public.user_preferences
  for each row execute function app_private.check_user_preferences();
revoke all on function app_private.check_user_preferences() from public, anon, authenticated;

grant update (favorite_competitions, level, onboarded_at) on public.user_preferences to authenticated;

-- Comptes créés avant ce lot : le parcours leur sera proposé une fois (ou passé).
