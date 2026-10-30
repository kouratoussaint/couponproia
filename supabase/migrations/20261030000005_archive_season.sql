-- =============================================================================
-- Coupon Pro IA — LOT 2 — Saison d'archive
-- L'offre gratuite d'API-Football ne donne accès qu'aux saisons 2022 à 2024.
-- Tant que ce réglage vaut une année, la synchronisation charge cette saison
-- (données réelles mais passées) et l'app l'affiche comme « archive ».
-- Repasser à null (saison en cours) après la souscription à l'offre Pro :
--   update public.app_settings set value = 'null' where key = 'sports.archive_season';
-- =============================================================================
insert into public.app_settings (key, value, is_public, description) values
  ('sports.archive_season', '2024'::jsonb, true,
   'Saison d''archive synchronisée à la place de la saison en cours (null = saison en cours)')
on conflict (key) do nothing;
