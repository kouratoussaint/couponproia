-- Tests pgTAP : empreinte et taille de l'APK publiées avec la version (LOT 26).
begin;
select plan(3);

insert into public.app_versions (platform, version_name, build_number, min_supported_build, download_url, sha256, size_bytes)
values ('android', '9.9.9', 2999, 2100, 'https://exemple.test/app.apk', repeat('a', 64), 32820320);

set local role anon;
select is((select sha256 || ':' || size_bytes from public.app_versions where version_name = '9.9.9'),
  repeat('a', 64) || ':32820320', 'empreinte et taille lisibles par l''app (même sans connexion)');
reset role;

select throws_ok($$ insert into public.app_versions (platform, version_name, build_number, min_supported_build, sha256)
                    values ('android', '9.9.8', 2998, 2100, 'pas-une-empreinte') $$, '23514', null, 'empreinte invalide refusée');
select throws_ok($$ insert into public.app_versions (platform, version_name, build_number, min_supported_build, size_bytes)
                    values ('android', '9.9.7', 2997, 2100, 0) $$, '23514', null, 'taille nulle refusée');

select * from finish();
rollback;
