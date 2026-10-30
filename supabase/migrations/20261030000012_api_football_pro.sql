-- =============================================================================
-- Coupon Pro IA — Passage à l'offre Pro d'API-Football (30/10/2026)
-- Fin du mode archive : saison en cours, cotes des matchs à venir, débit relevé
-- (7 500 requêtes/jour, marge conservée), historique 2025/26 chargé une fois.
-- Les relevés de cotes passent avant les générations de coupons (07:00, 13:00).
-- =============================================================================
update public.app_settings set value = 'null'::jsonb where key = 'sports.archive_season';
update public.app_settings set value = '250'::jsonb where key = 'sports.min_request_interval_ms';
update public.app_settings set value = '7000'::jsonb where key = 'sports.daily_request_budget';
update public.app_settings set value = '150'::jsonb where key = 'sports.odds_max_fixtures_per_run';

insert into public.app_settings (key, value, is_public, description) values
  ('sports.history_seasons', '[2025]'::jsonb, false,
   'Saisons passées chargées une seule fois (calendrier et résultats) pour l''historique du moteur')
on conflict (key) do update set value = excluded.value;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('sports-odds', '0 6,12,18 * * *', 'select app_private.invoke_sports_sync(''odds'')');
  end if;
end;
$$;
