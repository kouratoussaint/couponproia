-- =============================================================================
-- Coupon Pro IA — LOT 2 — Rythme des requêtes
-- L'offre gratuite d'API-Football limite aussi le débit à 10 requêtes par minute :
-- on espace les requêtes de 6,5 s. Avec l'offre Pro, ramener à 250 ms environ.
-- =============================================================================
insert into public.app_settings (key, value, is_public, description) values
  ('sports.min_request_interval_ms', '6500'::jsonb, false,
   'Délai minimal entre deux requêtes au fournisseur, en millisecondes (6500 pour l''offre gratuite)')
on conflict (key) do nothing;
