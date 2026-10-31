-- =============================================================================
-- Coupon Pro IA — Modification complète du profil (31/10)
-- Photo de profil : stockage public, écriture dans son propre dossier, 1 Mo maximum.
-- =============================================================================
do $do$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('profile-avatars', 'profile-avatars', true, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
  on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
  execute $p$create policy "photos de profil : ajout dans son dossier" on storage.objects for insert to authenticated
    with check (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "photos de profil : remplacement" on storage.objects for update to authenticated
    using (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
    with check (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "photos de profil : suppression" on storage.objects for delete to authenticated
    using (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "photos de profil : liste de son dossier" on storage.objects for select to authenticated
    using (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
end;
$do$;

-- La photo doit venir du stockage du projet (pas d'adresse externe arbitraire).
alter table public.profiles drop constraint if exists profiles_avatar_url_check;
alter table public.profiles add constraint profiles_avatar_url_check
  check (avatar_url is null or avatar_url ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/profile-avatars/');
