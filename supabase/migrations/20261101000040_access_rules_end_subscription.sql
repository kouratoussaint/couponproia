-- Règles d'accès du 01/11 (sauf super administrateur) :
--  - une analyse IA de match n'est lisible que par l'utilisateur qui l'a réalisée (ou payée) ;
--    l'analyse offerte du jour reste ouverte à tous ;
--  - forfait FREE : coupons et résultats visibles seulement après les matchs (2 h 15 après le coup
--    d'envoi du dernier match) ; forfaits payants : à tout moment ;
--  - forfait FREE : une analyse se paie en crédits (1 par défaut) ; on peut acheter des crédits seuls.
-- Et : « Mettre fin au forfait » (retour au forfait FREE).

insert into public.permissions (id, description) values
  ('analyses.read_all', 'Lire toutes les analyses IA de match (super administrateur)')
on conflict (id) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id) values ('super_admin', 'analyses.read_all')
on conflict do nothing;

insert into public.app_settings (key, value, is_public, description) values
  ('analysis.credit_cost', '1'::jsonb, true,
   'Crédits débités pour une analyse IA de match demandée avec le forfait FREE (0 = gratuite)')
on conflict (key) do nothing;

-- FREE : plus aucun coupon avant la fin des matchs (catégories vides).
update public.app_settings
   set value = (select jsonb_agg(case when p ->> 'code' = 'FREE'
                                      then jsonb_set(p, '{features,coupon_categories}', '[]'::jsonb) else p end)
                from jsonb_array_elements(value) p)
 where key = 'pricing.plans';

-- -----------------------------------------------------------------------------
-- Coupons : visibilité selon le forfait
-- -----------------------------------------------------------------------------
create or replace function app_private.can_see_coupon(p_user uuid, p_category text, p_first_kickoff timestamptz,
                                                      p_last_kickoff timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_last_kickoff, p_first_kickoff) + interval '2 hours 15 minutes' <= now()
      or app_private.has_permission(p_user, 'generation.manage')
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') = '"all"'::jsonb
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') ? p_category;
$$;
revoke all on function app_private.can_see_coupon(uuid, text, timestamptz, timestamptz) from public, anon;
grant execute on function app_private.can_see_coupon(uuid, text, timestamptz, timestamptz) to authenticated;

-- Ancienne signature (sans la fin des matchs) : désormais aussi stricte, pour tout appel restant.
create or replace function app_private.can_see_coupon_selections(p_user uuid, p_category text, p_first_kickoff timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select app_private.can_see_coupon(p_user, p_category, p_first_kickoff, p_first_kickoff + interval '4 hours'); $$;

drop policy "sélections des coupons visibles selon le forfait" on public.coupon_selections;
create policy "sélections des coupons visibles selon le forfait" on public.coupon_selections for select to authenticated
  using (exists (
    select 1 from public.coupons c
    where c.id = coupon_id
      and app_private.can_see_coupon((select auth.uid()), c.category, c.first_kickoff_at, c.last_kickoff_at)));

create or replace function public.coupon_analyses(p_ids uuid[])
returns table (id uuid, analysis jsonb, locked boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         case when not v.visible then jsonb_build_object('source', c.analysis ->> 'source')
              when t.tech then c.analysis
              else c.analysis - 'ai_provider' - 'ai_model' end,
         not v.visible
  from public.coupons c
  cross join lateral (select app_private.can_see_coupon((select auth.uid()), c.category, c.first_kickoff_at, c.last_kickoff_at) as visible) v
  cross join (select app_private.has_permission((select auth.uid()), 'ai.providers') as tech) t
  where c.id = any(p_ids)
    and cardinality(p_ids) <= 200
    -- Mêmes lignes que la politique de lecture des coupons
    and (c.status in ('published', 'withdrawn') or app_private.has_permission((select auth.uid()), 'generation.manage'));
$$;

create or replace function app_private.on_coupon_published()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
  r record;
begin
  if new.status <> 'published' or (tg_op = 'UPDATE' and old.status = 'published') or new.first_kickoff_at <= now() then
    return new;
  end if;
  select count(*) into v_n from public.coupon_selections where coupon_id = new.id;
  if v_n = 0 then
    return new;
  end if;
  for r in
    select up.user_id from public.user_preferences up join public.profiles p on p.id = up.user_id
    where up.notify_coupons and not p.is_suspended
      and (cardinality(up.coupon_categories) = 0 or new.category = any(up.coupon_categories))
      and app_private.can_see_coupon(up.user_id, new.category, new.first_kickoff_at, new.last_kickoff_at)
  loop
    perform app_private.notify(r.user_id, 'coupon', 'Nouveau coupon : ' || new.title,
      v_n || ' sélection' || case when v_n > 1 then 's' else '' end || ' · cote ' ||
      replace(to_char(new.total_odd, 'FM990.00'), '.', ',') || ' · premier match à ' ||
      to_char(new.first_kickoff_at at time zone 'Africa/Ouagadougou', 'HH24:MI') || '. Estimations, sans garantie.',
      '/coupon/' || new.id, 'coupon:' || new.id);
  end loop;
  return new;
end;
$$;

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
                     and app_private.can_see_coupon(v_user, c.category, c.first_kickoff_at, c.last_kickoff_at)) then
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

create or replace function public.set_coupon_watch(p_coupon uuid, p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if not p_on then
    delete from public.coupon_watches where user_id = v_user and coupon_id = p_coupon;
    return false;
  end if;
  if not exists (select 1 from public.coupons c
                 where c.id = p_coupon and c.status = 'published' and c.first_kickoff_at > now()
                   and app_private.can_see_coupon(v_user, c.category, c.first_kickoff_at, c.last_kickoff_at)) then
    raise exception 'Coupon non suivable (déjà commencé ou réservé)' using errcode = '22023';
  end if;
  if (select count(*) from public.coupon_watches where user_id = v_user) >= 50 then
    delete from public.coupon_watches w using public.coupons c
    where w.user_id = v_user and c.id = w.coupon_id and c.first_kickoff_at < now();
  end if;
  insert into public.coupon_watches (user_id, coupon_id) values (v_user, p_coupon) on conflict do nothing;
  return true;
end;
$$;

create or replace function app_private.on_match_analysed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_home text;
  v_away text;
  v_kickoff timestamptz;
begin
  select h.name, a.name, m.kickoff_at into v_home, v_away, v_kickoff
  from public.matches m join public.teams h on h.id = m.home_team_id join public.teams a on a.id = m.away_team_id
  where m.id = new.match_id and m.status = 'scheduled' and m.kickoff_at > now();
  if not found then
    return new;
  end if;
  for r in
    select distinct f.user_id, t.name as team
    from public.matches m
    join public.user_favorites f on f.team_id in (m.home_team_id, m.away_team_id)
    join public.teams t on t.id = f.team_id
    join public.profiles p on p.id = f.user_id and not p.is_suspended
    where m.id = new.match_id
  loop
    perform app_private.notify(r.user_id, 'analysis', 'Analyse prête : ' || v_home || ' – ' || v_away,
      r.team || ', votre équipe suivie, joue le ' || to_char(v_kickoff at time zone 'Africa/Ouagadougou', 'DD/MM à HH24:MI')
      || '. Ouvrez la fiche du match : « Analyser » donne accès à l''analyse (forfait, ou crédit avec FREE).',
      '/match/' || new.match_id, 'analysis:' || new.match_id);
  end loop;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Analyses : accès personnel
-- -----------------------------------------------------------------------------
create table public.analysis_access (
  user_id    uuid not null references auth.users(id) on delete cascade,
  match_id   bigint not null references public.matches(id) on delete cascade,
  source     text not null check (source in ('plan', 'credit', 'featured', 'history')),
  created_at timestamptz not null default now(),
  primary key (user_id, match_id)
);
create index analysis_access_match_idx on public.analysis_access (match_id);
create index analysis_access_day_idx on public.analysis_access (user_id, created_at);
revoke all on public.analysis_access from anon, authenticated;
grant select on public.analysis_access to authenticated;
alter table public.analysis_access enable row level security;
create policy "ses accès aux analyses" on public.analysis_access for select to authenticated
  using (user_id = (select auth.uid()));

-- Reprise : chacun garde les analyses qu'il a lui-même lancées.
insert into public.analysis_access (user_id, match_id, source, created_at)
select distinct on (r.user_id, r.match_id) r.user_id, r.match_id, 'history', r.created_at
from public.ai_requests r
where r.kind = 'match_analysis' and r.user_id is not null and r.match_id is not null
  and exists (select 1 from auth.users u where u.id = r.user_id)
  and exists (select 1 from public.matches m where m.id = r.match_id)
order by r.user_id, r.match_id, r.created_at
on conflict do nothing;

drop policy "analyses lisibles" on public.match_analyses;
create policy "analyses lisibles par leur auteur" on public.match_analyses for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'analyses.read_all')
         or exists (select 1 from public.analysis_access a
                    where a.user_id = (select auth.uid()) and a.match_id = match_analyses.match_id)
         or exists (select 1 from public.featured_matches f where f.match_id = match_analyses.match_id));

-- -----------------------------------------------------------------------------
-- « Mettre fin au forfait » : retour immédiat au forfait FREE, audité
-- -----------------------------------------------------------------------------
create or replace function public.admin_end_subscription(p_user uuid, p_reason text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_ended integer;
  v_removed integer;
  v_plan text;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'Motif obligatoire' using errcode = '22023';
  end if;
  v_plan := app_private.plan_of(p_user);
  -- Prolongations à venir : supprimées ; forfait en cours : terminé maintenant.
  delete from public.subscriptions where user_id = p_user and period_start > now();
  get diagnostics v_removed = row_count;
  update public.subscriptions set period_end = now(), note = coalesce(note || ' · ', '') || 'Arrêté : ' || btrim(p_reason)
   where user_id = p_user and period_start <= now() and period_end > now();
  get diagnostics v_ended = row_count;
  if v_ended + v_removed = 0 then
    raise exception 'Aucun forfait en cours : l''utilisateur est déjà au forfait FREE' using errcode = '22023';
  end if;
  perform app_private.refresh_plan_credits(p_user);
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'subscription.end', 'user', p_user::text,
          jsonb_build_object('plan', v_plan, 'reason', btrim(p_reason), 'ended', v_ended, 'removed_future', v_removed));
  return v_ended + v_removed;
end;
$$;
revoke all on function public.admin_end_subscription(uuid, text) from public, anon;
grant execute on function public.admin_end_subscription(uuid, text) to authenticated;
