-- LOT 7 : studio graphique.
-- Les visuels sont dessinés et exportés sur le téléphone (PNG, JPG, PDF) à partir des données d'un
-- coupon vérifié : aucun chiffre saisi à la main. Le serveur fournit les modèles, garde l'identité
-- visuelle de l'utilisateur, contrôle les droits (modèle, forfait, quota) et journalise chaque export.

-- -----------------------------------------------------------------------------
-- Avantages du studio par forfait (réglages, modifiables)
--   branding : none (aucun) / name (nom + couleurs) / full (nom, couleurs, logo, couverture, signature)
--   watermark : mention « Réalisé avec Coupon Pro IA » imposée
--   exports_per_day : nombre d'exports par jour
-- -----------------------------------------------------------------------------
update public.app_settings s
set value = (
  select jsonb_agg(
    jsonb_set(p, '{features,studio}', case p ->> 'code'
      when 'FREE'        then '{"branding": "none", "watermark": true,  "exports_per_day": 3}'::jsonb
      when 'STARTER'     then '{"branding": "name", "watermark": true,  "exports_per_day": 20}'::jsonb
      when 'PRO_TIPSTER' then '{"branding": "full", "watermark": false, "exports_per_day": 100}'::jsonb
      else                    '{"branding": "full", "watermark": false, "exports_per_day": 300}'::jsonb
    end, true) order by ord)
  from jsonb_array_elements(s.value) with ordinality as t(p, ord))
where key = 'pricing.plans';

-- Rang d'un forfait = sa position dans la grille (FREE 1, STARTER 2…).
create or replace function app_private.plan_rank(p_plan text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select ord::integer from public.app_settings s, jsonb_array_elements(s.value) with ordinality as t(p, ord)
                   where s.key = 'pricing.plans' and p ->> 'code' = p_plan), 1);
$$;

-- Mots interdits dans tout texte libre affiché sur un visuel (mêmes règles que l'IA).
create or replace function app_private.has_forbidden_words(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_text, '') ~* ('(^|[^[:alnum:]])('
    || 'sûr(e|s|es)?|sûrement|garanti(e|es|s|r|t)?|assuré(e|s|es)?|certitudes?|imparables?|infaillibles?|sans risque|gains?'
    || ')([^[:alnum:]]|$)')
    or coalesce(p_text, '') ~ '(^|[^[:alnum:]])100 ?%';
$$;

-- -----------------------------------------------------------------------------
-- Modèles graphiques (le dessin est dans l'app ; la base décide lesquels sont proposés et à qui)
-- -----------------------------------------------------------------------------
create table public.design_templates (
  code         text primary key check (code ~ '^[a-z_]+$'),
  name         text not null,
  description  text not null default '',
  min_plan     text not null default 'FREE',
  sort         smallint not null default 0,
  is_active    boolean not null default true,
  defaults     jsonb not null default '{}'::jsonb,
  updated_at   timestamptz not null default now()
);
create trigger design_templates_set_updated_at
  before update on public.design_templates
  for each row execute function app_private.set_updated_at();

insert into public.design_templates (code, name, description, min_plan, sort, defaults) values
  ('classique', 'Classique', 'Fond sombre, sélections en lignes, cote totale mise en avant', 'FREE', 1,
   '{"primary": "#0E7C47", "accent": "#F2C230"}'),
  ('clair', 'Clair', 'Fond clair et sobre, lisible en story', 'FREE', 2,
   '{"primary": "#0E7C47", "accent": "#0B3D2E"}'),
  ('ticket', 'Ticket', 'Présentation façon ticket, idéale pour WhatsApp', 'STARTER', 3,
   '{"primary": "#1F2A44", "accent": "#E4572E"}'),
  ('stade', 'Stade', 'Dégradé et lignes de terrain, cartes par match', 'STARTER', 4,
   '{"primary": "#14532D", "accent": "#A3E635"}'),
  ('prestige', 'Prestige', 'Image de couverture, logo et signature du Tipster', 'PRO_TIPSTER', 5,
   '{"primary": "#111827", "accent": "#D4AF37"}');

-- -----------------------------------------------------------------------------
-- Identité visuelle de l'utilisateur (Tipster)
-- -----------------------------------------------------------------------------
create table public.user_branding (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  display_name   text check (char_length(display_name) between 1 and 40),
  primary_color  text check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  accent_color   text check (accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  signature      text check (char_length(signature) between 1 and 80),
  logo_path      text,
  cover_path     text,
  updated_at     timestamptz not null default now(),
  check (logo_path is null or logo_path like user_id::text || '/%'),
  check (cover_path is null or cover_path like user_id::text || '/%')
);
create trigger user_branding_set_updated_at
  before update on public.user_branding
  for each row execute function app_private.set_updated_at();

create or replace function app_private.check_user_branding()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.user_branding;
  v_level text := coalesce(app_private.plan_features(app_private.plan_of(new.user_id)) -> 'studio' ->> 'branding', 'none');
begin
  if tg_op = 'UPDATE' then
    v_old := old;
  end if;
  if app_private.has_forbidden_words(new.display_name) or app_private.has_forbidden_words(new.signature) then
    raise exception 'Texte refusé : les pronostics sont des estimations (des mots comme « sûr », « garanti » ou « gain » sont interdits).'
      using errcode = '22023';
  end if;
  if app_private.has_permission(new.user_id, 'admin.access') then
    return new;
  end if;
  -- Seules les nouvelles valeurs sont contrôlées : effacer reste toujours possible.
  if v_level = 'none' and (
       (new.display_name is not null and new.display_name is distinct from v_old.display_name)
    or (new.primary_color is not null and new.primary_color is distinct from v_old.primary_color)
    or (new.accent_color is not null and new.accent_color is distinct from v_old.accent_color)) then
    raise exception 'Personnalisation disponible à partir du forfait STARTER' using errcode = '42501';
  end if;
  if v_level <> 'full' and (
       (new.logo_path is not null and new.logo_path is distinct from v_old.logo_path)
    or (new.cover_path is not null and new.cover_path is distinct from v_old.cover_path)
    or (new.signature is not null and new.signature is distinct from v_old.signature)) then
    raise exception 'Logo, couverture et signature disponibles à partir du forfait PRO TIPSTER' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger user_branding_check
  before insert or update on public.user_branding
  for each row execute function app_private.check_user_branding();

-- -----------------------------------------------------------------------------
-- Journal des exports (un export = un visuel produit sur le téléphone)
-- -----------------------------------------------------------------------------
create table public.generated_assets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  source_kind   text not null check (source_kind in ('platform', 'user')),
  source_id     uuid not null,
  template_code text not null references public.design_templates(code),
  format        text not null check (format in ('square', 'portrait', 'story', 'landscape')),
  file_type     text not null check (file_type in ('png', 'jpg', 'pdf')),
  created_at    timestamptz not null default now()
);
create index generated_assets_user_day_idx on public.generated_assets (user_id, created_at desc);

-- Droits du studio pour l'utilisateur connecté : modèles accessibles, personnalisation, quota.
create or replace function public.my_studio()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_plan text;
  v_studio jsonb;
  v_staff boolean;
  v_used integer;
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  v_plan := app_private.plan_of(v_user);
  v_studio := coalesce(app_private.plan_features(v_plan) -> 'studio',
                       '{"branding": "none", "watermark": true, "exports_per_day": 3}'::jsonb);
  v_staff := app_private.has_permission(v_user, 'admin.access');
  select count(*) into v_used from public.generated_assets
  where user_id = v_user and created_at >= date_trunc('day', now());
  return jsonb_build_object(
    'enabled', coalesce((select enabled from public.feature_flags where key = 'graphic_studio'), false),
    'plan', v_plan,
    'branding', case when v_staff then 'full' else v_studio ->> 'branding' end,
    'watermark', case when v_staff then false else coalesce((v_studio ->> 'watermark')::boolean, true) end,
    'exports_per_day', case when v_staff then null else (v_studio ->> 'exports_per_day')::integer end,
    'exports_today', v_used,
    'templates', coalesce((
      select jsonb_agg(jsonb_build_object('code', t.code, 'name', t.name, 'description', t.description,
               'min_plan', t.min_plan, 'defaults', t.defaults,
               'available', v_staff or app_private.plan_rank(v_plan) >= app_private.plan_rank(t.min_plan))
             order by t.sort)
      from public.design_templates t where t.is_active), '[]'::jsonb));
end;
$$;

-- Autorise et journalise un export. Appelé par l'app avant de produire le fichier.
create or replace function public.studio_export(p_source_kind text, p_source_id uuid, p_template text,
                                                p_format text, p_file_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_studio jsonb;
  v_staff boolean;
  v_template public.design_templates;
  v_limit integer;
  v_used integer;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if not coalesce((select enabled from public.feature_flags where key = 'graphic_studio'), false) then
    raise exception 'Studio indisponible' using errcode = '42501', hint = 'feature_disabled';
  end if;
  v_staff := app_private.has_permission(v_user, 'admin.access');
  v_studio := app_private.plan_features(app_private.plan_of(v_user)) -> 'studio';

  select * into v_template from public.design_templates where code = p_template and is_active;
  if not found then
    raise exception 'Modèle inconnu' using errcode = '22023', hint = 'invalid_template';
  end if;
  if not v_staff and app_private.plan_rank(app_private.plan_of(v_user)) < app_private.plan_rank(v_template.min_plan) then
    raise exception 'Modèle réservé au forfait %', v_template.min_plan using errcode = '42501', hint = 'template_locked';
  end if;

  -- Le coupon doit être visible en entier par l'utilisateur (aucun visuel d'un coupon réservé).
  if p_source_kind = 'platform' then
    if not exists (select 1 from public.coupons c
                   where c.id = p_source_id and c.status in ('published', 'withdrawn')
                     and app_private.can_see_coupon_selections(v_user, c.category, c.first_kickoff_at)) then
      raise exception 'Coupon indisponible' using errcode = '42501', hint = 'coupon_unavailable';
    end if;
  elsif p_source_kind = 'user' then
    if not exists (select 1 from public.user_coupons u where u.id = p_source_id and u.user_id = v_user) then
      raise exception 'Coupon indisponible' using errcode = '42501', hint = 'coupon_unavailable';
    end if;
  else
    raise exception 'Source inconnue' using errcode = '22023', hint = 'coupon_unavailable';
  end if;

  -- Quota quotidien (verrou par utilisateur : deux exports simultanés ne dépassent pas la limite).
  perform pg_advisory_xact_lock(hashtext('studio:' || v_user::text));
  v_limit := case when v_staff then null else coalesce((v_studio ->> 'exports_per_day')::integer, 3) end;
  select count(*) into v_used from public.generated_assets
  where user_id = v_user and created_at >= date_trunc('day', now());
  if v_limit is not null and v_used >= v_limit then
    raise exception 'Limite de % visuels par jour atteinte', v_limit using errcode = '42501', hint = 'quota_exceeded';
  end if;

  insert into public.generated_assets (user_id, source_kind, source_id, template_code, format, file_type)
  values (v_user, p_source_kind, p_source_id, p_template, p_format, p_file_type)
  returning id into v_id;
  return jsonb_build_object('asset_id', v_id, 'exports_today', v_used + 1, 'exports_per_day', v_limit);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privilèges et RLS
-- -----------------------------------------------------------------------------
revoke all on public.design_templates, public.user_branding, public.generated_assets from anon, authenticated;
grant select on public.design_templates to authenticated;
grant select, insert, update, delete on public.user_branding to authenticated;
grant select on public.generated_assets to authenticated;

alter table public.design_templates enable row level security;
alter table public.user_branding    enable row level security;
alter table public.generated_assets enable row level security;

create policy "modèles lisibles" on public.design_templates for select to authenticated using (true);
create policy "modèles gérés par l'équipe" on public.design_templates for all to authenticated
  using (app_private.has_permission((select auth.uid()), 'settings.manage'))
  with check (app_private.has_permission((select auth.uid()), 'settings.manage'));
grant insert, update, delete on public.design_templates to authenticated;

create policy "identité visuelle personnelle" on public.user_branding for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "exports personnels" on public.generated_assets for select to authenticated
  using (user_id = (select auth.uid()) or app_private.has_permission((select auth.uid()), 'admin.access'));

revoke all on function public.my_studio() from public, anon;
grant execute on function public.my_studio() to authenticated;
revoke all on function public.studio_export(text, uuid, text, text, text) from public, anon;
grant execute on function public.studio_export(text, uuid, text, text, text) to authenticated;
revoke all on function app_private.plan_rank(text) from public, anon, authenticated;
revoke all on function app_private.check_user_branding() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Stockage des logos et couvertures : dossier privé par utilisateur (<user_id>/…), 2 Mo max.
-- (Bloc ignoré par la base de test locale, qui n'a pas le schéma storage.)
-- -----------------------------------------------------------------------------
do $do$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('branding', 'branding', false, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
  on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

  execute $p$create policy "branding : lecture de son dossier" on storage.objects for select to authenticated
    using (bucket_id = 'branding' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "branding : ajout dans son dossier" on storage.objects for insert to authenticated
    with check (bucket_id = 'branding' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "branding : remplacement dans son dossier" on storage.objects for update to authenticated
    using (bucket_id = 'branding' and (storage.foldername(name))[1] = (select auth.uid())::text)
    with check (bucket_id = 'branding' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "branding : suppression dans son dossier" on storage.objects for delete to authenticated
    using (bucket_id = 'branding' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
end;
$do$;

update public.feature_flags set enabled = true, description = 'Studio graphique (LOT 7)' where key = 'graphic_studio';
