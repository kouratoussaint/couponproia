-- LOT 26 (validé le 07/11) : mise à jour téléchargée et installée par l'application.
-- Chaque version Android publie l'empreinte SHA-256 et la taille de son APK (arm64-v8a) :
-- l'app ne propose l'installation qu'après avoir vérifié le fichier reçu.
-- Rappel : build_number = numéro installé par Android pour arm64-v8a = 2000 + build.
alter table public.app_versions
  add column sha256 text check (sha256 ~ '^[0-9a-f]{64}$'),
  add column size_bytes bigint check (size_bytes > 0);
comment on column public.app_versions.sha256 is 'Empreinte SHA-256 de l''APK arm64-v8a (SHA256SUMS.txt de la release)';
comment on column public.app_versions.size_bytes is 'Taille de l''APK arm64-v8a, en octets';
comment on column public.app_versions.build_number is 'Numéro de version Android installé pour arm64-v8a : 2000 + build (APK découpé par architecture)';
