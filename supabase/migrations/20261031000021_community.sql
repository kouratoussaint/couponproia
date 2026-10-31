-- LOT 10 : Tipsters et communauté.
--
-- Principes :
--  * Un Tipster publie un de ses coupons enregistrés AVANT le premier coup d'envoi. Une fois publié,
--    le coupon est immuable (ni modification, ni archivage, ni suppression, sauf suppression du
--    compte) : les pertes restent visibles.
--  * Les statistiques d'un Tipster sont calculées par la plateforme, uniquement sur ses coupons
--    publiés et réglés automatiquement (LOT 8). Aucun chiffre n'est saisi par le Tipster.
--  * Suivre, réagir, commenter, signaler, bloquer ; modération par les rôles autorisés.
--  * Équipes favorites (user_favorites) pour l'accueil.
--  * Pas de parrainage (décision du propriétaire).

-- -----------------------------------------------------------------------------
-- Qui peut publier : permission tipster.publish (rôle Tipster) ou forfait qui l'inclut
-- -----------------------------------------------------------------------------
update public.app_settings s
set value = (
  select jsonb_agg(jsonb_set(p, '{features,tipster_publish}',
           to_jsonb(p ->> 'code' in ('PRO_TIPSTER', 'BUSINESS')), true) order by ord)
  from jsonb_array_elements(s.value) with ordinality as t(p, ord))
where key = 'pricing.plans';

insert into public.app_settings (key, value, is_public, description) values
  ('community.min_settled_for_rate', '10'::jsonb, true,
   'Nombre de coupons réglés avant d''afficher le taux de réussite d''un Tipster'),
  ('community.max_coupon_posts_per_day', '10'::jsonb, true, 'Coupons publiés par Tipster et par jour'),
  ('community.max_text_posts_per_day', '10'::jsonb, true, 'Publications texte par Tipster et par jour'),
  ('community.max_comments_per_hour', '30'::jsonb, false, 'Commentaires par utilisateur et par heure'),
  ('community.publish_min_minutes_before_kickoff', '5'::jsonb, true,
   'Délai minimal entre la publication d''un coupon et son premier coup d''envoi')
on conflict (key) do nothing;

create or replace function app_private.setting_int(p_key text, p_default integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$ select coalesce((select (value #>> '{}')::integer from public.app_settings where key = p_key), p_default); $$;

create or replace function app_private.flag_on(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select coalesce((select enabled from public.feature_flags where key = p_key), false); $$;

create or replace function app_private.can_publish_as_tipster(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.has_permission(p_user, 'tipster.publish')
      or coalesce((app_private.plan_features(app_private.plan_of(p_user)) ->> 'tipster_publish')::boolean, false);
$$;

-- -----------------------------------------------------------------------------
-- Profils Tipsters
-- -----------------------------------------------------------------------------
create table public.tipster_profiles (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  handle           text not null check (handle ~ '^[a-z0-9_]{3,20}$'),
  display_name     text not null check (char_length(display_name) between 2 and 40),
  bio              text check (char_length(bio) <= 280),
  avatar_path      text,
  status           text not null default 'active' check (status in ('active', 'suspended')),
  status_note      text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (avatar_path is null or avatar_path like user_id::text || '/%')
);
create unique index tipster_profiles_handle_idx on public.tipster_profiles (handle);
create trigger tipster_profiles_set_updated_at
  before update on public.tipster_profiles
  for each row execute function app_private.set_updated_at();

create or replace function app_private.check_tipster_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.handle := lower(new.handle);
  if app_private.has_forbidden_words(new.display_name) or app_private.has_forbidden_words(new.bio)
     or app_private.has_forbidden_words(new.handle) then
    raise exception 'Texte refusé : les pronostics sont des estimations (des mots comme « sûr », « garanti » ou « gain » sont interdits).'
      using errcode = '22023';
  end if;
  if tg_op = 'INSERT' and not app_private.can_publish_as_tipster(new.user_id) then
    raise exception 'Profil Tipster disponible avec le forfait PRO TIPSTER ou BUSINESS' using errcode = '42501';
  end if;
  -- Le statut ne change que par la modération.
  if tg_op = 'UPDATE' and (new.status is distinct from old.status or new.status_note is distinct from old.status_note)
     and not app_private.has_permission((select auth.uid()), 'moderation.manage')
     and (select auth.uid()) is not null then
    raise exception 'Statut modifiable par la modération uniquement' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and (select auth.uid()) is not null then
    new.status := 'active';
    new.status_note := null;
  end if;
  return new;
end;
$$;
create trigger tipster_profiles_check
  before insert or update on public.tipster_profiles
  for each row execute function app_private.check_tipster_profile();

-- -----------------------------------------------------------------------------
-- Blocages et visibilité
-- -----------------------------------------------------------------------------
create table public.user_blocks (
  blocker_id  uuid not null references auth.users(id) on delete cascade,
  blocked_id  uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create or replace function app_private.blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.user_blocks
                 where (blocker_id = p_a and blocked_id = p_b) or (blocker_id = p_b and blocked_id = p_a));
$$;

-- Un Tipster est visible s'il est actif et qu'aucun blocage n'existe entre lui et le lecteur.
create or replace function app_private.tipster_visible(p_tipster uuid, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_tipster = p_viewer
      or app_private.has_permission(p_viewer, 'moderation.manage')
      or (exists (select 1 from public.tipster_profiles t where t.user_id = p_tipster and t.status = 'active')
          and not app_private.blocked_between(p_tipster, p_viewer));
$$;

-- -----------------------------------------------------------------------------
-- Coupons publiés : immuables
-- -----------------------------------------------------------------------------
alter table public.user_coupons
  add column published_at timestamptz,
  add column publish_comment text check (char_length(publish_comment) <= 500);
create index user_coupons_published_idx on public.user_coupons (user_id, published_at desc) where published_at is not null;

create or replace function app_private.protect_published_user_coupon()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Suppression du compte (cascade) : seul cas où un coupon publié peut disparaître.
  if pg_trigger_depth() > 1 and tg_op = 'DELETE' then
    return old;
  end if;
  if tg_op = 'DELETE' then
    if old.published_at is not null then
      raise exception 'Un coupon publié ne peut pas être supprimé' using errcode = '42501';
    end if;
    return old;
  end if;
  if old.published_at is not null then
    if new.published_at is distinct from old.published_at
       or new.publish_comment is distinct from old.publish_comment
       or new.title is distinct from old.title
       or new.status is distinct from old.status
       or new.total_odd is distinct from old.total_odd
       or new.combined_probability is distinct from old.combined_probability
       or new.implied_probability is distinct from old.implied_probability
       or new.risk_level is distinct from old.risk_level
       or new.analysis is distinct from old.analysis
       or new.fingerprint is distinct from old.fingerprint
       or new.criteria is distinct from old.criteria
       or new.user_id is distinct from old.user_id then
      raise exception 'Un coupon publié est immuable (seul son résultat évolue)' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger user_coupons_protect_published
  before update or delete on public.user_coupons
  for each row execute function app_private.protect_published_user_coupon();

create or replace function app_private.protect_published_user_selection()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_coupon uuid := case when tg_op = 'INSERT' then new.coupon_id else old.coupon_id end;
begin
  if pg_trigger_depth() > 1 and tg_op = 'DELETE' then
    return old;
  end if;
  if exists (select 1 from public.user_coupons c where c.id = v_coupon and c.published_at is not null) then
    if tg_op = 'UPDATE' and (to_jsonb(new) - 'result') = (to_jsonb(old) - 'result') then
      return new; -- règlement
    end if;
    raise exception 'Les sélections d''un coupon publié sont immuables' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
create trigger user_coupon_selections_protect_published
  before insert or update or delete on public.user_coupon_selections
  for each row execute function app_private.protect_published_user_selection();

create policy "coupons publiés des tipsters" on public.user_coupons for select to authenticated
  using (published_at is not null and app_private.tipster_visible(user_id, (select auth.uid())));
create policy "sélections des coupons publiés" on public.user_coupon_selections for select to authenticated
  using (exists (select 1 from public.user_coupons c
                 where c.id = coupon_id and c.published_at is not null
                   and app_private.tipster_visible(c.user_id, (select auth.uid()))));

-- -----------------------------------------------------------------------------
-- Publications, réactions, commentaires, abonnements, signalements, favoris
-- -----------------------------------------------------------------------------
create table public.posts (
  id          bigint generated always as identity primary key,
  author_id   uuid not null references public.tipster_profiles(user_id) on delete cascade,
  kind        text not null check (kind in ('coupon', 'text')),
  coupon_id   uuid unique references public.user_coupons(id) on delete cascade,
  body        text check (char_length(body) <= 1000),
  status      text not null default 'visible' check (status in ('visible', 'hidden')),
  status_note text,
  created_at  timestamptz not null default now(),
  check ((kind = 'coupon') = (coupon_id is not null)),
  check (kind = 'coupon' or char_length(coalesce(body, '')) >= 1)
);
create index posts_feed_idx on public.posts (created_at desc) where status = 'visible';
create index posts_author_idx on public.posts (author_id, created_at desc);

create table public.post_reactions (
  post_id     bigint not null references public.posts(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.comments (
  id          bigint generated always as identity primary key,
  post_id     bigint not null references public.posts(id) on delete cascade,
  author_id   uuid not null references auth.users(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 500),
  status      text not null default 'visible' check (status in ('visible', 'hidden')),
  created_at  timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);
create index comments_author_idx on public.comments (author_id, created_at desc);

create table public.tipster_followers (
  follower_id  uuid not null references auth.users(id) on delete cascade,
  tipster_id   uuid not null references public.tipster_profiles(user_id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, tipster_id),
  check (follower_id <> tipster_id)
);
create index tipster_followers_tipster_idx on public.tipster_followers (tipster_id);

create table public.reports (
  id           bigint generated always as identity primary key,
  reporter_id  uuid not null references auth.users(id) on delete cascade,
  target_type  text not null check (target_type in ('post', 'comment', 'tipster')),
  target_id    text not null,
  reason       text not null check (reason in ('spam', 'arnaque', 'insulte', 'faux_resultats', 'autre')),
  details      text check (char_length(details) <= 500),
  status       text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  resolution   text,
  resolved_by  uuid references auth.users(id) on delete set null,
  resolved_at  timestamptz,
  created_at   timestamptz not null default now()
);
create unique index reports_open_once_idx on public.reports (reporter_id, target_type, target_id) where status = 'open';
create index reports_open_idx on public.reports (created_at) where status = 'open';

create table public.user_favorites (
  user_id     uuid not null references auth.users(id) on delete cascade,
  team_id     bigint not null references public.teams(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, team_id)
);

-- Textes : mêmes mots interdits ; limites de fréquence.
create or replace function app_private.check_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if app_private.has_forbidden_words(new.body) then
      raise exception 'Texte refusé : pas de promesse de résultat (« sûr », « garanti », « gain »…).' using errcode = '22023';
    end if;
    if (select count(*) from public.comments where author_id = new.author_id and created_at > now() - interval '1 hour')
       >= app_private.setting_int('community.max_comments_per_hour', 30) then
      raise exception 'Trop de commentaires en peu de temps, réessayez plus tard' using errcode = '42501', hint = 'rate_limited';
    end if;
  elsif new.body is distinct from old.body or new.post_id is distinct from old.post_id or new.author_id is distinct from old.author_id then
    raise exception 'Un commentaire ne se modifie pas' using errcode = '42501';
  elsif new.status is distinct from old.status and not app_private.has_permission((select auth.uid()), 'moderation.manage')
        and (select auth.uid()) is not null then
    raise exception 'Statut modifiable par la modération uniquement' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger comments_check before insert or update on public.comments
  for each row execute function app_private.check_comment();

-- Une publication visible, d'un Tipster visible pour ce lecteur.
create or replace function app_private.post_visible(p_post bigint, p_viewer uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.posts p
                 where p.id = p_post
                   and (p.status = 'visible' or p.author_id = p_viewer
                        or app_private.has_permission(p_viewer, 'moderation.manage'))
                   and app_private.tipster_visible(p.author_id, p_viewer));
$$;

-- -----------------------------------------------------------------------------
-- RLS
-- -----------------------------------------------------------------------------
revoke all on public.tipster_profiles, public.user_blocks, public.posts, public.post_reactions,
  public.comments, public.tipster_followers, public.reports, public.user_favorites from anon, authenticated;

grant select, insert on public.tipster_profiles to authenticated;
grant update (handle, display_name, bio, avatar_path) on public.tipster_profiles to authenticated;
grant select, insert, delete on public.user_blocks, public.post_reactions, public.tipster_followers,
  public.user_favorites to authenticated;
grant select, delete on public.posts to authenticated;
grant select, insert, delete on public.comments to authenticated;
grant select, insert on public.reports to authenticated;

alter table public.tipster_profiles  enable row level security;
alter table public.user_blocks       enable row level security;
alter table public.posts             enable row level security;
alter table public.post_reactions    enable row level security;
alter table public.comments          enable row level security;
alter table public.tipster_followers enable row level security;
alter table public.reports           enable row level security;
alter table public.user_favorites    enable row level security;

create policy "profils tipsters visibles" on public.tipster_profiles for select to authenticated
  using (app_private.tipster_visible(user_id, (select auth.uid())));
create policy "créer son profil tipster" on public.tipster_profiles for insert to authenticated
  with check (user_id = (select auth.uid()) and app_private.flag_on('tipsters'));
create policy "modifier son profil tipster" on public.tipster_profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "ses blocages" on public.user_blocks for all to authenticated
  using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));

create policy "publications visibles" on public.posts for select to authenticated
  using (app_private.post_visible(id, (select auth.uid())));
-- Seules les publications texte se suppriment : un coupon publié reste (pertes comprises).
create policy "supprimer ses publications texte" on public.posts for delete to authenticated
  using (author_id = (select auth.uid()) and kind = 'text');

create policy "réactions visibles" on public.post_reactions for select to authenticated
  using (app_private.post_visible(post_id, (select auth.uid())));
create policy "réagir" on public.post_reactions for insert to authenticated
  with check (user_id = (select auth.uid()) and app_private.flag_on('community')
              and app_private.post_visible(post_id, (select auth.uid())));
create policy "retirer sa réaction" on public.post_reactions for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "commentaires visibles" on public.comments for select to authenticated
  using (app_private.post_visible(post_id, (select auth.uid()))
         and (status = 'visible' or author_id = (select auth.uid())
              or app_private.has_permission((select auth.uid()), 'moderation.manage'))
         and not app_private.blocked_between(author_id, (select auth.uid())));
create policy "commenter" on public.comments for insert to authenticated
  with check (author_id = (select auth.uid()) and app_private.flag_on('community')
              and exists (select 1 from public.posts p where p.id = post_id and p.status = 'visible'
                          and app_private.tipster_visible(p.author_id, (select auth.uid()))));
create policy "supprimer ses commentaires" on public.comments for delete to authenticated
  using (author_id = (select auth.uid()));

create policy "abonnements visibles" on public.tipster_followers for select to authenticated
  using (follower_id = (select auth.uid()) or tipster_id = (select auth.uid()));
create policy "suivre un tipster" on public.tipster_followers for insert to authenticated
  with check (follower_id = (select auth.uid()) and app_private.flag_on('tipsters')
              and exists (select 1 from public.tipster_profiles t where t.user_id = tipster_id and t.status = 'active')
              and not app_private.blocked_between(tipster_id, (select auth.uid())));
create policy "ne plus suivre" on public.tipster_followers for delete to authenticated
  using (follower_id = (select auth.uid()));

create policy "ses signalements" on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()) or app_private.has_permission((select auth.uid()), 'moderation.manage'));
create policy "signaler" on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid()) and status = 'open' and resolution is null
              and resolved_by is null and resolved_at is null);

create policy "ses équipes favorites" on public.user_favorites for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- Publier
-- -----------------------------------------------------------------------------
create or replace function public.publish_user_coupon(p_coupon uuid, p_comment text default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_coupon public.user_coupons;
  v_first timestamptz;
  v_count integer;
  v_post bigint;
  v_comment text := nullif(btrim(p_comment), '');
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if not app_private.flag_on('tipsters') then
    raise exception 'Publication momentanément indisponible' using errcode = '42501', hint = 'feature_disabled';
  end if;
  if not app_private.can_publish_as_tipster(v_user) then
    raise exception 'Publication réservée aux forfaits PRO TIPSTER et BUSINESS' using errcode = '42501', hint = 'plan_required';
  end if;
  if not exists (select 1 from public.tipster_profiles where user_id = v_user and status = 'active') then
    raise exception 'Créez d''abord votre profil Tipster' using errcode = '42501', hint = 'profile_required';
  end if;
  select * into v_coupon from public.user_coupons where id = p_coupon and user_id = v_user for update;
  if not found then
    raise exception 'Coupon introuvable' using errcode = 'P0002';
  end if;
  if v_coupon.published_at is not null then
    raise exception 'Coupon déjà publié' using errcode = '22023', hint = 'already_published';
  end if;
  if v_coupon.status = 'archived' then
    raise exception 'Coupon archivé' using errcode = '22023';
  end if;
  if app_private.has_forbidden_words(v_comment) then
    raise exception 'Texte refusé : pas de promesse de résultat (« sûr », « garanti », « gain »…).' using errcode = '22023';
  end if;
  if char_length(v_comment) > 500 then
    raise exception 'Commentaire trop long (500 caractères maximum)' using errcode = '22023';
  end if;
  select min(m.kickoff_at), count(*) into v_first, v_count
  from public.user_coupon_selections s join public.matches m on m.id = s.match_id
  where s.coupon_id = p_coupon;
  if v_count = 0 then
    raise exception 'Coupon vide' using errcode = '22023';
  end if;
  if v_first <= now() + make_interval(mins => app_private.setting_int('community.publish_min_minutes_before_kickoff', 5)) then
    raise exception 'Trop tard : un coupon se publie avant le premier coup d''envoi' using errcode = '22023', hint = 'too_late';
  end if;
  if (select count(*) from public.posts where author_id = v_user and kind = 'coupon' and created_at > now() - interval '1 day')
     >= app_private.setting_int('community.max_coupon_posts_per_day', 10) then
    raise exception 'Limite de publications de coupons atteinte pour aujourd''hui' using errcode = '42501', hint = 'rate_limited';
  end if;

  update public.user_coupons
  set status = 'saved', published_at = now(), publish_comment = v_comment
  where id = p_coupon;
  insert into public.posts (author_id, kind, coupon_id, body) values (v_user, 'coupon', p_coupon, v_comment)
  returning id into v_post;
  return v_post;
end;
$$;

create or replace function public.create_text_post(p_body text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_body text := btrim(coalesce(p_body, ''));
  v_post bigint;
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if not app_private.flag_on('community') then
    raise exception 'Publication momentanément indisponible' using errcode = '42501', hint = 'feature_disabled';
  end if;
  if not exists (select 1 from public.tipster_profiles where user_id = v_user and status = 'active') then
    raise exception 'Créez d''abord votre profil Tipster' using errcode = '42501', hint = 'profile_required';
  end if;
  if char_length(v_body) not between 1 and 1000 then
    raise exception 'Texte vide ou trop long (1 000 caractères maximum)' using errcode = '22023';
  end if;
  if app_private.has_forbidden_words(v_body) then
    raise exception 'Texte refusé : pas de promesse de résultat (« sûr », « garanti », « gain »…).' using errcode = '22023';
  end if;
  if (select count(*) from public.posts where author_id = v_user and kind = 'text' and created_at > now() - interval '1 day')
     >= app_private.setting_int('community.max_text_posts_per_day', 10) then
    raise exception 'Limite de publications atteinte pour aujourd''hui' using errcode = '42501', hint = 'rate_limited';
  end if;
  insert into public.posts (author_id, kind, body) values (v_user, 'text', v_body) returning id into v_post;
  return v_post;
end;
$$;

-- -----------------------------------------------------------------------------
-- Statistiques vérifiées d'un Tipster
-- -----------------------------------------------------------------------------
create or replace function app_private.tipster_stats_raw(p_tipster uuid, p_days integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with pub as (
    select c.* from public.user_coupons c
    where c.user_id = p_tipster and c.published_at is not null
      and (p_days is null or c.published_at >= now() - make_interval(days => p_days))
  ),
  settled as (select * from pub where result in ('won', 'lost'))
  select jsonb_build_object(
    'published', (select count(*) from pub),
    'won', (select count(*) from pub where result = 'won'),
    'lost', (select count(*) from pub where result = 'lost'),
    'void', (select count(*) from pub where result = 'void'),
    'pending', (select count(*) from pub where result is null),
    'win_rate', (select round(count(*) filter (where result = 'won')::numeric / nullif(count(*), 0), 4) from settled),
    'average_odd', (select round(avg(total_odd), 2) from settled),
    'theoretical_return', (select round((coalesce(sum(settled_odd) filter (where result = 'won'), 0) - count(*)) / nullif(count(*), 0), 4) from settled),
    'last_results', coalesce((select jsonb_agg(r order by s desc) from
                       (select result as r, coalesce(settled_at, published_at) as s from pub where result is not null
                        order by coalesce(settled_at, published_at) desc limit 10) t), '[]'::jsonb)
  );
$$;

create or replace function public.tipster_stats(p_tipster uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_min integer := app_private.setting_int('community.min_settled_for_rate', 10);
  v_all jsonb;
begin
  if not app_private.tipster_visible(p_tipster, auth.uid()) then
    raise exception 'Tipster introuvable' using errcode = 'P0002';
  end if;
  v_all := app_private.tipster_stats_raw(p_tipster, null);
  return jsonb_build_object(
    'all_time', v_all,
    'last_30_days', app_private.tipster_stats_raw(p_tipster, 30),
    'min_settled_for_rate', v_min,
    'stake_note', 'Mise théorique de 1 unité par coupon (aucun pari réel)',
    'scope', 'Coupons publiés avant le premier coup d''envoi, réglés automatiquement par Coupon Pro IA',
    'followers', (select count(*) from public.tipster_followers where tipster_id = p_tipster),
    'computed_at', now());
end;
$$;

-- -----------------------------------------------------------------------------
-- Fil, annuaire
-- -----------------------------------------------------------------------------
create or replace function app_private.post_json(p public.posts, p_viewer uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'kind', p.kind, 'body', p.body, 'status', p.status, 'created_at', p.created_at,
    'author', (select jsonb_build_object('user_id', t.user_id, 'handle', t.handle, 'display_name', t.display_name,
                                         'avatar_path', t.avatar_path)
               from public.tipster_profiles t where t.user_id = p.author_id),
    'reactions', (select count(*) from public.post_reactions r where r.post_id = p.id),
    'my_reaction', exists (select 1 from public.post_reactions r where r.post_id = p.id and r.user_id = p_viewer),
    'comments', (select count(*) from public.comments c where c.post_id = p.id and c.status = 'visible'
                   and not app_private.blocked_between(c.author_id, p_viewer)),
    'is_mine', p.author_id = p_viewer,
    'coupon', case when p.coupon_id is null then null else (
      select jsonb_build_object(
        'id', c.id, 'title', c.title, 'total_odd', c.total_odd, 'combined_probability', c.combined_probability,
        'result', c.result, 'settled_odd', c.settled_odd, 'published_at', c.published_at,
        'selections', coalesce((select jsonb_agg(jsonb_build_object(
            'position', s.position, 'selection_key', s.selection_key, 'odd', s.odd, 'result', s.result,
            'match', jsonb_build_object('id', m.id, 'kickoff_at', m.kickoff_at, 'status', m.status,
                       'home_goals', m.home_goals, 'away_goals', m.away_goals,
                       'home', jsonb_build_object('name', h.name, 'logo_url', h.logo_url),
                       'away', jsonb_build_object('name', a.name, 'logo_url', a.logo_url),
                       'competition', jsonb_build_object('name', k.name))) order by s.position)
          from public.user_coupon_selections s
          join public.matches m on m.id = s.match_id
          join public.teams h on h.id = m.home_team_id
          join public.teams a on a.id = m.away_team_id
          join public.competitions k on k.id = m.competition_id
          where s.coupon_id = c.id), '[]'::jsonb))
      from public.user_coupons c where c.id = p.coupon_id) end);
$$;

create or replace function public.community_feed(p_scope text default 'all', p_tipster uuid default null,
                                                 p_before timestamptz default null, p_limit integer default 20)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(app_private.post_json(p, auth.uid()) order by p.created_at desc), '[]'::jsonb)
  from (
    select p.* from public.posts p
    where auth.uid() is not null
      and (p.status = 'visible' or p.author_id = auth.uid())
      and app_private.tipster_visible(p.author_id, auth.uid())
      and (p_before is null or p.created_at < p_before)
      and case p_scope
            when 'following' then exists (select 1 from public.tipster_followers f
                                          where f.follower_id = auth.uid() and f.tipster_id = p.author_id)
            when 'tipster' then p.author_id = p_tipster
            else true end
    order by p.created_at desc
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
  ) p;
$$;

create or replace function public.post_detail(p_post bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.posts;
begin
  select * into v_post from public.posts where id = p_post;
  if not found or not app_private.post_visible(p_post, auth.uid()) then
    raise exception 'Publication introuvable' using errcode = 'P0002';
  end if;
  return app_private.post_json(v_post, auth.uid()) || jsonb_build_object(
    'comment_list', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'body', c.body, 'created_at', c.created_at, 'status', c.status,
               'is_mine', c.author_id = auth.uid(),
               'author_id', c.author_id,
               'author', coalesce((select t.display_name from public.tipster_profiles t where t.user_id = c.author_id),
                                  (select pr.display_name from public.profiles pr where pr.id = c.author_id)),
               'author_is_tipster', exists (select 1 from public.tipster_profiles t where t.user_id = c.author_id))
             order by c.created_at)
      from public.comments c
      where c.post_id = p_post
        and (c.status = 'visible' or c.author_id = auth.uid())
        and not app_private.blocked_between(c.author_id, auth.uid())), '[]'::jsonb));
end;
$$;

create or replace function public.tipsters_directory(p_query text default null, p_limit integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x order by (x ->> 'settled_30d')::int desc, (x ->> 'followers')::int desc, x ->> 'display_name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'user_id', t.user_id, 'handle', t.handle, 'display_name', t.display_name, 'bio', t.bio,
      'avatar_path', t.avatar_path,
      'followers', (select count(*) from public.tipster_followers f where f.tipster_id = t.user_id),
      'i_follow', exists (select 1 from public.tipster_followers f where f.tipster_id = t.user_id and f.follower_id = auth.uid()),
      'settled_30d', (select count(*) from public.user_coupons c where c.user_id = t.user_id and c.published_at is not null
                        and c.result in ('won', 'lost') and c.published_at >= now() - interval '30 days'),
      'stats_30d', app_private.tipster_stats_raw(t.user_id, 30)) as x
    from public.tipster_profiles t
    where auth.uid() is not null
      and t.status = 'active'
      and not app_private.blocked_between(t.user_id, auth.uid())
      and (p_query is null or t.handle ilike '%' || p_query || '%' or t.display_name ilike '%' || p_query || '%')
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
  ) t;
$$;

-- Droits communauté de l'utilisateur connecté.
create or replace function public.my_community()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'tipsters_enabled', app_private.flag_on('tipsters'),
    'community_enabled', app_private.flag_on('community'),
    'can_publish', app_private.can_publish_as_tipster(auth.uid()),
    'can_moderate', app_private.has_permission(auth.uid(), 'moderation.manage'),
    'profile', (select to_jsonb(t) - 'status_note' from public.tipster_profiles t where t.user_id = auth.uid()),
    'following', (select count(*) from public.tipster_followers where follower_id = auth.uid()),
    'open_reports', case when app_private.has_permission(auth.uid(), 'moderation.manage')
                         then (select count(*) from public.reports where status = 'open') end);
$$;

-- Utilisateurs bloqués (avec leur nom affiché).
create or replace function public.my_blocks()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', b.blocked_id,
           'name', coalesce((select t.display_name from public.tipster_profiles t where t.user_id = b.blocked_id),
                            (select pr.display_name from public.profiles pr where pr.id = b.blocked_id), 'Utilisateur'),
           'created_at', b.created_at) order by b.created_at desc), '[]'::jsonb)
  from public.user_blocks b where b.blocker_id = auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- Modération (journalisée)
-- -----------------------------------------------------------------------------
create or replace function public.moderate(p_target_type text, p_target_id text, p_action text,
                                           p_note text default null, p_report bigint default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'moderation.manage') then
    raise exception 'Action réservée à la modération' using errcode = '42501';
  end if;
  if p_action not in ('dismiss', 'hide', 'restore', 'suspend', 'reactivate') then
    raise exception 'Action inconnue' using errcode = '22023';
  end if;
  if p_action in ('hide', 'restore') then
    if p_target_type = 'post' then
      update public.posts set status = case p_action when 'hide' then 'hidden' else 'visible' end, status_note = p_note
      where id = p_target_id::bigint;
    elsif p_target_type = 'comment' then
      update public.comments set status = case p_action when 'hide' then 'hidden' else 'visible' end
      where id = p_target_id::bigint;
    else
      raise exception 'Cible incompatible' using errcode = '22023';
    end if;
  elsif p_action in ('suspend', 'reactivate') then
    if p_target_type <> 'tipster' then
      raise exception 'Cible incompatible' using errcode = '22023';
    end if;
    update public.tipster_profiles set status = case p_action when 'suspend' then 'suspended' else 'active' end,
           status_note = p_note
    where user_id = p_target_id::uuid;
  end if;
  if p_report is not null then
    update public.reports set status = case p_action when 'dismiss' then 'dismissed' else 'resolved' end,
           resolution = coalesce(p_note, p_action), resolved_by = v_actor, resolved_at = now()
    where id = p_report;
  elsif p_action <> 'dismiss' then
    -- Les autres signalements ouverts sur la même cible sont traités du même coup.
    update public.reports set status = 'resolved', resolution = coalesce(p_note, p_action), resolved_by = v_actor, resolved_at = now()
    where target_type = p_target_type and target_id = p_target_id and status = 'open';
  end if;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'moderation.' || p_action, p_target_type, p_target_id,
          jsonb_build_object('note', p_note, 'report', p_report));
end;
$$;

-- Signalements à traiter, avec un aperçu de la cible.
create or replace function public.moderation_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'moderation.manage') then
    raise exception 'Action réservée à la modération' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'target_type', r.target_type, 'target_id', r.target_id, 'reason', r.reason,
      'details', r.details, 'created_at', r.created_at,
      'reports_on_target', (select count(*) from public.reports o where o.target_type = r.target_type
                              and o.target_id = r.target_id and o.status = 'open'),
      'preview', case r.target_type
        when 'post' then (select jsonb_build_object('text', coalesce(p.body, '(coupon)'), 'status', p.status,
                                  'author', t.display_name, 'author_id', p.author_id)
                          from public.posts p join public.tipster_profiles t on t.user_id = p.author_id
                          where p.id = r.target_id::bigint)
        when 'comment' then (select jsonb_build_object('text', c.body, 'status', c.status, 'author_id', c.author_id,
                                     'author', (select pr.display_name from public.profiles pr where pr.id = c.author_id))
                             from public.comments c where c.id = r.target_id::bigint)
        else (select jsonb_build_object('text', coalesce(t.bio, ''), 'status', t.status, 'author', t.display_name,
                                        'author_id', t.user_id)
              from public.tipster_profiles t where t.user_id = r.target_id::uuid) end)
      order by r.created_at)
    from public.reports r where r.status = 'open'), '[]'::jsonb);
end;
$$;

revoke all on function public.publish_user_coupon(uuid, text), public.create_text_post(text),
  public.tipster_stats(uuid), public.community_feed(text, uuid, timestamptz, integer), public.post_detail(bigint),
  public.tipsters_directory(text, integer), public.my_community(), public.my_blocks(),
  public.moderate(text, text, text, text, bigint), public.moderation_queue() from public, anon;
grant execute on function public.publish_user_coupon(uuid, text), public.create_text_post(text),
  public.tipster_stats(uuid), public.community_feed(text, uuid, timestamptz, integer), public.post_detail(bigint),
  public.tipsters_directory(text, integer), public.my_community(), public.my_blocks(),
  public.moderate(text, text, text, text, bigint), public.moderation_queue() to authenticated;
-- Fonctions internes : appelées seulement par les fonctions ci-dessus…
revoke all on function app_private.setting_int(text, integer), app_private.can_publish_as_tipster(uuid),
  app_private.tipster_stats_raw(uuid, integer), app_private.post_json(public.posts, uuid) from public, anon, authenticated;
-- … sauf celles utilisées par les règles d'accès (évaluées avec les droits du lecteur).
revoke all on function app_private.flag_on(text), app_private.blocked_between(uuid, uuid),
  app_private.tipster_visible(uuid, uuid), app_private.post_visible(bigint, uuid) from public, anon;
grant execute on function app_private.flag_on(text), app_private.blocked_between(uuid, uuid),
  app_private.tipster_visible(uuid, uuid), app_private.post_visible(bigint, uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Photos de profil des Tipsters : publiques (lecture), écriture dans son dossier, 1 Mo.
-- -----------------------------------------------------------------------------
do $do$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('tipster-avatars', 'tipster-avatars', true, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
  on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;
  execute $p$create policy "avatars tipster : ajout dans son dossier" on storage.objects for insert to authenticated
    with check (bucket_id = 'tipster-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "avatars tipster : remplacement" on storage.objects for update to authenticated
    using (bucket_id = 'tipster-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
    with check (bucket_id = 'tipster-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "avatars tipster : suppression" on storage.objects for delete to authenticated
    using (bucket_id = 'tipster-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
  execute $p$create policy "avatars tipster : liste de son dossier" on storage.objects for select to authenticated
    using (bucket_id = 'tipster-avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)$p$;
end;
$do$;

update public.feature_flags set enabled = true where key in ('tipsters', 'community');
