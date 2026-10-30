-- =============================================================================
-- Coupon Pro IA — LOT 1 — Fondations
-- Profils, préférences, rôles et permissions, feature flags, réglages,
-- versions de l'application, journal d'audit.
--
-- Règle d'or : le client (rôles anon / authenticated) LIT ce que la RLS
-- autorise et n'ÉCRIT que des colonnes explicitement accordées. Tout ce qui
-- touche aux rôles, flags, réglages et à l'audit passe par des fonctions
-- SECURITY DEFINER qui vérifient les permissions côté serveur.
-- =============================================================================

create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Utilitaires
-- -----------------------------------------------------------------------------
create or replace function app_private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Rôles et permissions
-- -----------------------------------------------------------------------------
create table public.roles (
  id          text primary key check (id ~ '^[a-z_]+$'),
  label       text not null,
  rank        smallint not null unique,
  created_at  timestamptz not null default now()
);
comment on table public.roles is 'Rôles applicatifs. visitor = non connecté (aucune ligne user_roles).';

create table public.permissions (
  id           text primary key check (id ~ '^[a-z_]+(\.[a-z_]+)+$'),
  description  text not null,
  created_at   timestamptz not null default now()
);

create table public.role_permissions (
  role_id        text not null references public.roles(id) on delete cascade,
  permission_id  text not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table public.user_roles (
  user_id     uuid not null references auth.users(id) on delete cascade,
  role_id     text not null references public.roles(id) on delete restrict,
  granted_by  uuid references auth.users(id) on delete set null,
  granted_at  timestamptz not null default now(),
  primary key (user_id, role_id)
);
create index user_roles_role_idx on public.user_roles(role_id);

-- -----------------------------------------------------------------------------
-- Profils et préférences
-- -----------------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null check (char_length(display_name) between 2 and 40),
  avatar_url    text check (avatar_url is null or avatar_url ~ '^https://'),
  country_code  char(2) not null default 'BF' check (country_code ~ '^[A-Z]{2}$'),
  timezone      text not null default 'Africa/Ouagadougou',
  locale        text not null default 'fr' check (locale in ('fr')),
  is_suspended  boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function app_private.set_updated_at();

create table public.user_preferences (
  user_id                uuid primary key references auth.users(id) on delete cascade,
  theme_mode             text not null default 'system' check (theme_mode in ('system', 'light', 'dark')),
  notifications_enabled  boolean not null default true,
  data_saver             boolean not null default false,
  updated_at             timestamptz not null default now()
);
create trigger user_preferences_set_updated_at
  before update on public.user_preferences
  for each row execute function app_private.set_updated_at();

-- -----------------------------------------------------------------------------
-- Pilotage : feature flags, réglages, versions de l'app
-- -----------------------------------------------------------------------------
create table public.feature_flags (
  key          text primary key check (key ~ '^[a-z_]+$'),
  enabled      boolean not null default false,
  description  text not null,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id) on delete set null
);
create trigger feature_flags_set_updated_at
  before update on public.feature_flags
  for each row execute function app_private.set_updated_at();

create table public.app_settings (
  key          text primary key check (key ~ '^[a-z_]+(\.[a-z_]+)*$'),
  value        jsonb not null,
  is_public    boolean not null default false,
  description  text not null,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users(id) on delete set null
);
create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function app_private.set_updated_at();

create table public.app_versions (
  id                   bigint generated always as identity primary key,
  platform             text not null check (platform in ('android', 'ios')),
  version_name         text not null check (version_name ~ '^\d+\.\d+\.\d+$'),
  build_number         integer not null check (build_number > 0),
  min_supported_build  integer not null check (min_supported_build > 0),
  download_url         text check (download_url is null or download_url ~ '^https://'),
  release_notes        text,
  published_at         timestamptz not null default now(),
  unique (platform, build_number),
  check (min_supported_build <= build_number)
);

-- -----------------------------------------------------------------------------
-- Journal d'audit (ajout seul)
-- -----------------------------------------------------------------------------
create table public.audit_logs (
  id           bigint generated always as identity primary key,
  actor_id     uuid references auth.users(id) on delete set null,
  action       text not null,
  target_type  text,
  target_id    text,
  details      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create index audit_logs_created_idx on public.audit_logs (created_at desc);
create index audit_logs_target_idx on public.audit_logs (target_type, target_id);

-- -----------------------------------------------------------------------------
-- Contrôle des permissions (source unique de vérité)
-- -----------------------------------------------------------------------------
create or replace function app_private.has_permission(p_user uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = p_user
      and rp.permission_id = p_permission
      and not p.is_suspended
  );
$$;

revoke all on function app_private.has_permission(uuid, text) from public;
grant execute on function app_private.has_permission(uuid, text) to anon, authenticated, service_role;

-- Permissions de l'utilisateur courant (pour afficher ou masquer des entrées d'interface ;
-- l'interface n'est jamais la barrière de sécurité : la RLS et les RPC le sont).
create or replace function public.my_permissions()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select distinct rp.permission_id
  from public.user_roles ur
  join public.role_permissions rp on rp.role_id = ur.role_id
  join public.profiles p on p.id = ur.user_id
  where ur.user_id = auth.uid()
    and not p.is_suspended;
$$;
revoke all on function public.my_permissions() from public, anon;
grant execute on function public.my_permissions() to authenticated;

-- -----------------------------------------------------------------------------
-- Création automatique du profil à l'inscription
-- -----------------------------------------------------------------------------
create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  v_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '');
  if v_name is null or char_length(v_name) < 2 then
    v_name := split_part(coalesce(new.email, ''), '@', 1);
  end if;
  if v_name is null or char_length(v_name) < 2 then
    v_name := 'Utilisateur';
  end if;
  v_name := left(v_name, 40);

  insert into public.profiles (id, display_name) values (new.id, v_name);
  insert into public.user_preferences (user_id) values (new.id);
  insert into public.user_roles (user_id, role_id) values (new.id, 'user');
  return new;
end;
$$;
revoke all on function app_private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app_private.handle_new_user();

-- -----------------------------------------------------------------------------
-- RPC d'administration (toutes auditées)
-- -----------------------------------------------------------------------------
create or replace function public.admin_set_user_role(p_target uuid, p_role text, p_grant boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'users.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if not exists (select 1 from public.roles where id = p_role) then
    raise exception 'Rôle inconnu : %', p_role using errcode = '22023';
  end if;
  if p_role in ('admin', 'super_admin') and not app_private.has_permission(v_actor, 'admins.manage') then
    raise exception 'Seul un super administrateur peut gérer ce rôle' using errcode = '42501';
  end if;
  if p_role = 'user' and not p_grant then
    raise exception 'Le rôle user ne peut pas être retiré' using errcode = '22023';
  end if;
  if p_target = v_actor and not p_grant then
    raise exception 'Impossible de retirer ses propres rôles' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = p_target) then
    raise exception 'Utilisateur introuvable' using errcode = 'P0002';
  end if;

  if p_grant then
    insert into public.user_roles (user_id, role_id, granted_by)
    values (p_target, p_role, v_actor)
    on conflict (user_id, role_id) do nothing;
  else
    delete from public.user_roles where user_id = p_target and role_id = p_role;
  end if;

  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor,
          case when p_grant then 'role.grant' else 'role.revoke' end,
          'user', p_target::text,
          jsonb_build_object('role', p_role));
end;
$$;
revoke all on function public.admin_set_user_role(uuid, text, boolean) from public, anon;
grant execute on function public.admin_set_user_role(uuid, text, boolean) to authenticated;

create or replace function public.admin_set_user_suspended(p_target uuid, p_suspended boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'users.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_target = v_actor then
    raise exception 'Impossible de se suspendre soi-même' using errcode = '42501';
  end if;
  if exists (select 1 from public.user_roles where user_id = p_target and role_id in ('admin', 'super_admin'))
     and not app_private.has_permission(v_actor, 'admins.manage') then
    raise exception 'Seul un super administrateur peut suspendre un administrateur' using errcode = '42501';
  end if;

  update public.profiles set is_suspended = p_suspended where id = p_target;
  if not found then
    raise exception 'Utilisateur introuvable' using errcode = 'P0002';
  end if;

  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, case when p_suspended then 'user.suspend' else 'user.reactivate' end,
          'user', p_target::text, '{}'::jsonb);
end;
$$;
revoke all on function public.admin_set_user_suspended(uuid, boolean) from public, anon;
grant execute on function public.admin_set_user_suspended(uuid, boolean) to authenticated;

create or replace function public.admin_set_feature_flag(p_key text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old boolean;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'flags.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  select enabled into v_old from public.feature_flags where key = p_key for update;
  if not found then
    raise exception 'Flag inconnu : %', p_key using errcode = 'P0002';
  end if;
  update public.feature_flags set enabled = p_enabled, updated_by = v_actor where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'flag.set', 'feature_flag', p_key,
          jsonb_build_object('from', v_old, 'to', p_enabled));
end;
$$;
revoke all on function public.admin_set_feature_flag(text, boolean) from public, anon;
grant execute on function public.admin_set_feature_flag(text, boolean) to authenticated;

-- Désigne le premier super administrateur. Volontairement NON accordée aux
-- rôles client : à exécuter une seule fois depuis l'éditeur SQL Supabase.
--   select app_private.bootstrap_super_admin('ton-email@exemple.com');
create or replace function app_private.bootstrap_super_admin(p_email text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  select id into v_user from auth.users where lower(email) = lower(p_email);
  if v_user is null then
    raise exception 'Aucun compte pour %', p_email using errcode = 'P0002';
  end if;
  insert into public.user_roles (user_id, role_id) values (v_user, 'super_admin')
  on conflict do nothing;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (null, 'role.bootstrap', 'user', v_user::text, jsonb_build_object('role', 'super_admin'));
end;
$$;
revoke all on function app_private.bootstrap_super_admin(text) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Privilèges : on retire les écritures par défaut, puis on accorde au cas par cas
-- -----------------------------------------------------------------------------
revoke insert, update, delete, truncate on
  public.roles, public.permissions, public.role_permissions, public.user_roles,
  public.profiles, public.user_preferences, public.feature_flags, public.app_settings,
  public.app_versions, public.audit_logs
from anon, authenticated;

revoke select on public.user_roles, public.profiles, public.user_preferences,
  public.audit_logs from anon;

grant select on public.roles, public.permissions, public.role_permissions,
  public.feature_flags, public.app_settings, public.app_versions to anon, authenticated;
grant select on public.user_roles, public.profiles, public.user_preferences,
  public.audit_logs to authenticated;

-- Seules ces colonnes sont modifiables par l'utilisateur lui-même.
grant update (display_name, avatar_url, country_code, timezone) on public.profiles to authenticated;
grant update (theme_mode, notifications_enabled, data_saver) on public.user_preferences to authenticated;

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.roles             enable row level security;
alter table public.permissions       enable row level security;
alter table public.role_permissions  enable row level security;
alter table public.user_roles        enable row level security;
alter table public.profiles          enable row level security;
alter table public.user_preferences  enable row level security;
alter table public.feature_flags     enable row level security;
alter table public.app_settings      enable row level security;
alter table public.app_versions      enable row level security;
alter table public.audit_logs        enable row level security;

create policy "roles lisibles" on public.roles
  for select to anon, authenticated using (true);
create policy "permissions lisibles" on public.permissions
  for select to anon, authenticated using (true);
create policy "role_permissions lisibles" on public.role_permissions
  for select to anon, authenticated using (true);

create policy "ses rôles ou gestionnaire" on public.user_roles
  for select to authenticated
  using (user_id = (select auth.uid())
         or app_private.has_permission((select auth.uid()), 'users.manage'));

create policy "son profil ou gestionnaire" on public.profiles
  for select to authenticated
  using (id = (select auth.uid())
         or app_private.has_permission((select auth.uid()), 'users.manage'));
create policy "modifier son profil" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "ses préférences" on public.user_preferences
  for select to authenticated
  using (user_id = (select auth.uid()));
create policy "modifier ses préférences" on public.user_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "flags lisibles" on public.feature_flags
  for select to anon, authenticated using (true);

create policy "réglages publics ou gestionnaire" on public.app_settings
  for select to anon, authenticated
  using (is_public
         or app_private.has_permission((select auth.uid()), 'settings.manage'));

create policy "versions lisibles" on public.app_versions
  for select to anon, authenticated using (true);

create policy "audit réservé" on public.audit_logs
  for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'audit.read'));
