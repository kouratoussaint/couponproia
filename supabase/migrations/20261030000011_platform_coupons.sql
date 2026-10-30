-- =============================================================================
-- Coupon Pro IA — LOT 4 — Coupons générés par la plateforme
-- Profils de génération (programmés ou continus), journal des générations, coupons
-- et sélections, historique des statuts. Un coupon publié est immuable : toute
-- correction passe par un changement de statut historisé (jamais en silence).
-- Écritures réservées au serveur (Edge Function coupon-engine) et à des RPC
-- d'administration auditées (permission generation.manage).
-- =============================================================================

create table public.coupon_profiles (
  id                               bigint generated always as identity primary key,
  key                              text not null unique check (key ~ '^[a-z0-9_]+$'),
  name                             text not null,
  category                         text not null check (category in (
                                     'du_jour', 'prudent', 'equilibre', 'audacieux', 'cote_elevee',
                                     'multi_competitions', 'competition', 'marche', 'strategie')),
  description                      text,
  is_active                        boolean not null default false,
  mode                             text not null default 'scheduled' check (mode in ('scheduled', 'continuous')),
  publish_mode                     text not null default 'auto' check (publish_mode in ('auto', 'review')),
  -- Heures locales (app.timezone) de génération ; publication publish_delay_minutes plus tard.
  generate_times                   text[] not null default '{07:00}'
                                     check (array_position(generate_times, null) is null),
  publish_delay_minutes            integer not null default 60 check (publish_delay_minutes between 0 and 720),
  continuous_min_interval_minutes  integer not null default 180 check (continuous_min_interval_minutes >= 30),
  criteria                         jsonb not null default '{}'::jsonb,
  sort                             smallint not null default 100,
  created_at                       timestamptz not null default now(),
  updated_at                       timestamptz not null default now(),
  updated_by                       uuid references auth.users(id) on delete set null
);
create trigger coupon_profiles_set_updated_at
  before update on public.coupon_profiles
  for each row execute function app_private.set_updated_at();

create table public.generation_runs (
  id               bigint generated always as identity primary key,
  profile_id       bigint not null references public.coupon_profiles(id) on delete cascade,
  trigger          text not null check (trigger in ('schedule', 'continuous', 'manual')),
  -- Créneau (« 2026-11-02 07:00 ») : une génération programmée ne tourne qu'une fois par créneau.
  slot_key         text,
  status           text not null default 'running'
                     check (status in ('running', 'success', 'partial', 'refused', 'failed')),
  candidates       integer not null default 0,
  coupons_created  integer not null default 0,
  reasons          jsonb not null default '[]'::jsonb,
  details          jsonb not null default '{}'::jsonb,
  started_at       timestamptz not null default now(),
  finished_at      timestamptz,
  actor_id         uuid references auth.users(id) on delete set null
);
create unique index generation_runs_slot_idx on public.generation_runs (profile_id, slot_key) where slot_key is not null;
create index generation_runs_started_idx on public.generation_runs (started_at desc);

create table public.coupons (
  id                    uuid primary key default gen_random_uuid(),
  profile_id            bigint references public.coupon_profiles(id) on delete set null,
  run_id                bigint references public.generation_runs(id) on delete set null,
  source                text not null default 'platform' check (source in ('platform')),
  category              text not null,
  title                 text not null,
  description           text not null,
  risk_level            text not null check (risk_level in ('prudent', 'equilibre', 'audacieux')),
  total_odd             numeric(9, 2) not null check (total_odd > 1),
  combined_probability  numeric(6, 4) not null check (combined_probability > 0 and combined_probability <= 1),
  implied_probability   numeric(6, 4),
  status                text not null check (status in (
                          'pending_review', 'ready', 'published', 'rejected', 'expired', 'withdrawn')),
  publish_at            timestamptz not null,
  published_at          timestamptz,
  first_kickoff_at      timestamptz not null,
  last_kickoff_at       timestamptz not null,
  engine_version        text not null,
  data_source           text not null default 'API-Football',
  analysis              jsonb not null default '{}'::jsonb,
  fingerprint           text not null,
  -- Motif du dernier changement de statut (repris dans l'historique)
  status_note           text,
  -- Règlement (LOT 8)
  result                text check (result in ('won', 'lost', 'void')),
  settled_at            timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
-- Pas deux coupons identiques en circulation (mêmes matchs, mêmes issues).
create unique index coupons_fingerprint_live_idx on public.coupons (fingerprint)
  where status in ('pending_review', 'ready', 'published');
create index coupons_published_idx on public.coupons (published_at desc) where status = 'published';
create index coupons_due_idx on public.coupons (publish_at) where status = 'ready';
create trigger coupons_set_updated_at
  before update on public.coupons
  for each row execute function app_private.set_updated_at();

create table public.coupon_selections (
  id                   bigint generated always as identity primary key,
  coupon_id            uuid not null references public.coupons(id) on delete cascade,
  position             smallint not null,
  match_id             bigint not null references public.matches(id),
  market_code          text not null references public.markets(code),
  outcome_code         text not null,
  line                 numeric(4, 1),
  selection_key        text not null,
  odd                  numeric(7, 3) not null check (odd > 1),
  odd_best             numeric(7, 3),
  bookmakers           smallint,
  odds_captured_at     timestamptz not null,
  model_probability    numeric(6, 4) not null,
  implied_probability  numeric(6, 4),
  edge                 numeric(6, 4),
  reliability          text not null check (reliability in ('faible', 'moyenne', 'bonne')),
  justification        text not null,
  result               text check (result in ('won', 'lost', 'void')),
  -- Incompatibilité de base : jamais deux sélections du même match dans un coupon.
  unique (coupon_id, match_id),
  unique (coupon_id, position)
);
create index coupon_selections_match_idx on public.coupon_selections (match_id);

create table public.coupon_status_history (
  id           bigint generated always as identity primary key,
  coupon_id    uuid not null references public.coupons(id) on delete cascade,
  from_status  text,
  to_status    text not null,
  reason       text,
  actor_id     uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index coupon_status_history_coupon_idx on public.coupon_status_history (coupon_id, created_at);

-- -----------------------------------------------------------------------------
-- Historique automatique des statuts (motif : réglage de session app.status_reason)
-- -----------------------------------------------------------------------------
create or replace function app_private.log_coupon_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.coupon_status_history (coupon_id, from_status, to_status, reason, actor_id)
    values (new.id, case when tg_op = 'UPDATE' then old.status end, new.status,
            coalesce(nullif(current_setting('app.status_reason', true), ''), new.status_note), auth.uid());
  end if;
  return new;
end;
$$;
create trigger coupons_log_status
  after insert or update of status on public.coupons
  for each row execute function app_private.log_coupon_status();

-- -----------------------------------------------------------------------------
-- Immuabilité : le contenu d'un coupon publié (ou retiré) ne change plus.
-- Seuls le statut (retrait), le règlement et la date de mise à jour peuvent évoluer.
-- -----------------------------------------------------------------------------
create or replace function app_private.protect_published_coupon()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('published', 'withdrawn') and (
       new.title, new.description, new.category, new.risk_level, new.total_odd,
       new.combined_probability, new.implied_probability, new.analysis, new.fingerprint,
       new.engine_version, new.published_at, new.publish_at, new.first_kickoff_at, new.last_kickoff_at
     ) is distinct from (
       old.title, old.description, old.category, old.risk_level, old.total_odd,
       old.combined_probability, old.implied_probability, old.analysis, old.fingerprint,
       old.engine_version, old.published_at, old.publish_at, old.first_kickoff_at, old.last_kickoff_at
     ) then
    raise exception 'Un coupon publié est immuable : retirez-le et publiez une correction'
      using errcode = '42501';
  end if;
  if old.status in ('published', 'withdrawn') and new.status not in ('published', 'withdrawn') then
    raise exception 'Statut % impossible pour un coupon publié', new.status using errcode = '22023';
  end if;
  return new;
end;
$$;
create trigger coupons_protect_published
  before update on public.coupons
  for each row execute function app_private.protect_published_coupon();

create or replace function app_private.protect_published_selection()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status text;
begin
  select status into v_status from public.coupons where id = old.coupon_id;
  if v_status in ('published', 'withdrawn') then
    if tg_op = 'DELETE' then
      raise exception 'Sélection d''un coupon publié : suppression impossible' using errcode = '42501';
    end if;
    if (new.match_id, new.market_code, new.outcome_code, new.line, new.odd, new.odd_best,
        new.model_probability, new.implied_probability, new.edge, new.justification, new.position)
       is distinct from
       (old.match_id, old.market_code, old.outcome_code, old.line, old.odd, old.odd_best,
        old.model_probability, old.implied_probability, old.edge, old.justification, old.position) then
      raise exception 'Sélection d''un coupon publié : contenu immuable' using errcode = '42501';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
create trigger coupon_selections_protect
  before update or delete on public.coupon_selections
  for each row execute function app_private.protect_published_selection();

-- -----------------------------------------------------------------------------
-- Privilèges et RLS
-- -----------------------------------------------------------------------------
revoke all on public.coupon_profiles, public.generation_runs, public.coupons,
  public.coupon_selections, public.coupon_status_history from anon, authenticated;
grant select on public.coupon_profiles, public.generation_runs, public.coupons,
  public.coupon_selections, public.coupon_status_history to authenticated;

alter table public.coupon_profiles        enable row level security;
alter table public.generation_runs        enable row level security;
alter table public.coupons                enable row level security;
alter table public.coupon_selections      enable row level security;
alter table public.coupon_status_history  enable row level security;

create policy "profils : gestionnaires" on public.coupon_profiles for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'generation.manage'));
create policy "générations : gestionnaires" on public.generation_runs for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'generation.manage'));
-- Coupons publiés (et retraits, pour la transparence) visibles par tous les connectés.
-- LOT 9 : visibilité selon le forfait.
create policy "coupons publiés ou gestionnaire" on public.coupons for select to authenticated
  using (status in ('published', 'withdrawn')
         or app_private.has_permission((select auth.uid()), 'generation.manage'));
create policy "sélections des coupons visibles" on public.coupon_selections for select to authenticated
  using (exists (select 1 from public.coupons c where c.id = coupon_id));
create policy "historique des coupons visibles" on public.coupon_status_history for select to authenticated
  using (exists (select 1 from public.coupons c where c.id = coupon_id));

-- -----------------------------------------------------------------------------
-- RPC d'administration (auditées)
-- -----------------------------------------------------------------------------

-- Validation humaine : un coupon « à valider » devient « prêt » (publié à son heure,
-- ou tout de suite si elle est passée) ou « rejeté ».
create or replace function public.admin_review_coupon(p_coupon uuid, p_approve boolean, p_reason text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_coupon public.coupons;
  v_new text;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'generation.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  select * into v_coupon from public.coupons where id = p_coupon for update;
  if not found then
    raise exception 'Coupon introuvable' using errcode = 'P0002';
  end if;
  if v_coupon.status <> 'pending_review' then
    raise exception 'Ce coupon n''est pas en attente de validation (%)', v_coupon.status using errcode = '22023';
  end if;
  if p_approve and v_coupon.first_kickoff_at <= now() then
    raise exception 'Un match du coupon a déjà commencé : validation impossible' using errcode = '22023';
  end if;
  v_new := case when p_approve then 'ready' else 'rejected' end;
  perform set_config('app.status_reason',
    coalesce(nullif(trim(p_reason), ''), case when p_approve then 'Validé par un administrateur' else 'Rejeté par un administrateur' end),
    true);
  update public.coupons set status = v_new where id = p_coupon;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'coupon.review', 'coupon', p_coupon::text, jsonb_build_object('approve', p_approve, 'reason', p_reason));
  return v_new;
end;
$$;

-- Retrait d'un coupon publié (erreur constatée) : le contenu reste visible, marqué retiré.
create or replace function public.admin_withdraw_coupon(p_coupon uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'generation.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Motif obligatoire' using errcode = '22023';
  end if;
  perform set_config('app.status_reason', p_reason, true);
  update public.coupons set status = 'withdrawn' where id = p_coupon and status = 'published';
  if not found then
    raise exception 'Coupon publié introuvable' using errcode = 'P0002';
  end if;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'coupon.withdraw', 'coupon', p_coupon::text, jsonb_build_object('reason', p_reason));
end;
$$;

-- Réglage d'un profil : activation, modes, horaires, critères (fusionnés).
create or replace function public.admin_update_coupon_profile(p_profile bigint, p_patch jsonb)
returns public.coupon_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.coupon_profiles;
  v_new public.coupon_profiles;
  v_key text;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'generation.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if v_key not in ('name', 'description', 'is_active', 'mode', 'publish_mode', 'generate_times',
                     'publish_delay_minutes', 'continuous_min_interval_minutes', 'criteria') then
      raise exception 'Champ non modifiable : %', v_key using errcode = '22023';
    end if;
  end loop;
  if p_patch ? 'generate_times' and exists (
       select 1 from jsonb_array_elements_text(p_patch -> 'generate_times') t
       where t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
    raise exception 'Heure invalide (format HH:MM attendu)' using errcode = '22023';
  end if;
  select * into v_old from public.coupon_profiles where id = p_profile for update;
  if not found then
    raise exception 'Profil introuvable' using errcode = 'P0002';
  end if;
  update public.coupon_profiles set
    name = coalesce(p_patch ->> 'name', name),
    description = case when p_patch ? 'description' then p_patch ->> 'description' else description end,
    is_active = coalesce((p_patch ->> 'is_active')::boolean, is_active),
    mode = coalesce(p_patch ->> 'mode', mode),
    publish_mode = coalesce(p_patch ->> 'publish_mode', publish_mode),
    generate_times = case when p_patch ? 'generate_times'
      then array(select jsonb_array_elements_text(p_patch -> 'generate_times') order by 1) else generate_times end,
    publish_delay_minutes = coalesce((p_patch ->> 'publish_delay_minutes')::integer, publish_delay_minutes),
    continuous_min_interval_minutes = coalesce((p_patch ->> 'continuous_min_interval_minutes')::integer,
                                               continuous_min_interval_minutes),
    criteria = case when p_patch ? 'criteria' then criteria || (p_patch -> 'criteria') else criteria end,
    updated_by = v_actor
  where id = p_profile
  returning * into v_new;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'coupon_profile.update', 'coupon_profile', p_profile::text,
          jsonb_build_object('patch', p_patch, 'before', to_jsonb(v_old)));
  return v_new;
end;
$$;

revoke all on function public.admin_review_coupon(uuid, boolean, text) from public, anon;
revoke all on function public.admin_withdraw_coupon(uuid, text) from public, anon;
revoke all on function public.admin_update_coupon_profile(bigint, jsonb) from public, anon;
grant execute on function public.admin_review_coupon(uuid, boolean, text) to authenticated;
grant execute on function public.admin_withdraw_coupon(uuid, text) to authenticated;
grant execute on function public.admin_update_coupon_profile(bigint, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- Profils par défaut, drapeaux et réglages
-- Critères : cotes (sélection et totale), nombre de sélections, marchés, seuils du modèle,
-- fenêtre de matchs, fraîcheur des cotes. Tous modifiables depuis l'app (administration).
-- -----------------------------------------------------------------------------
insert into public.coupon_profiles
  (key, name, category, description, is_active, mode, publish_mode, generate_times, publish_delay_minutes, sort, criteria)
values
  ('du_jour', 'Coupon du jour', 'du_jour',
   'Les sélections que le moteur estime les plus solides parmi les matchs du jour.',
   true, 'scheduled', 'auto', '{07:00}', 60, 10,
   '{"min_selections": 2, "max_selections": 4, "min_total_odd": 2.5, "max_total_odd": 5,
     "min_selection_odd": 1.25, "max_selection_odd": 2.6, "coupons_per_run": 1,
     "markets": ["1X2", "DC"], "min_model_probability": 0.5, "min_edge": -0.02,
     "min_reliability": "moyenne", "window_hours": 24, "min_minutes_before_kickoff": 30,
     "max_odds_age_hours": 12, "require_validated_markets": true}'),
  ('prudent', 'Coupon prudent', 'prudent',
   'Peu de sélections, issues jugées les plus probables par le modèle. Profil de risque estimé, pas une garantie.',
   true, 'scheduled', 'auto', '{07:00, 13:00}', 60, 20,
   '{"min_selections": 2, "max_selections": 3, "min_total_odd": 1.6, "max_total_odd": 2.6,
     "min_selection_odd": 1.15, "max_selection_odd": 1.8, "coupons_per_run": 1,
     "markets": ["1X2", "DC"], "min_model_probability": 0.62, "min_edge": -0.03,
     "min_reliability": "moyenne", "window_hours": 24, "min_minutes_before_kickoff": 30,
     "max_odds_age_hours": 12, "require_validated_markets": true}'),
  ('equilibre', 'Coupon équilibré', 'equilibre',
   'Compromis entre probabilité estimée et cote.',
   true, 'scheduled', 'auto', '{07:00}', 60, 30,
   '{"min_selections": 3, "max_selections": 4, "min_total_odd": 4, "max_total_odd": 8,
     "min_selection_odd": 1.35, "max_selection_odd": 2.8, "coupons_per_run": 1,
     "markets": ["1X2", "DC"], "min_model_probability": 0.45, "min_edge": 0,
     "min_reliability": "moyenne", "window_hours": 36, "min_minutes_before_kickoff": 30,
     "max_odds_age_hours": 12, "require_validated_markets": true}'),
  ('audacieux', 'Coupon audacieux', 'audacieux',
   'Cote plus élevée, probabilité estimée plus faible. Profil de risque estimé, pas une garantie.',
   true, 'scheduled', 'auto', '{07:00}', 60, 40,
   '{"min_selections": 3, "max_selections": 6, "min_total_odd": 8, "max_total_odd": 25,
     "min_selection_odd": 1.5, "max_selection_odd": 4, "coupons_per_run": 1,
     "markets": ["1X2", "DC"], "min_model_probability": 0.33, "min_edge": 0.02,
     "min_reliability": "moyenne", "window_hours": 48, "min_minutes_before_kickoff": 30,
     "max_odds_age_hours": 12, "require_validated_markets": true}'),
  ('cote_elevee', 'Cote élevée', 'cote_elevee',
   'Pour viser une grosse cote : très risqué.',
   false, 'scheduled', 'review', '{07:00}', 60, 50,
   '{"min_selections": 4, "max_selections": 8, "min_total_odd": 20, "max_total_odd": 80,
     "min_selection_odd": 1.6, "max_selection_odd": 5, "coupons_per_run": 1,
     "markets": ["1X2", "DC"], "min_model_probability": 0.28, "min_edge": 0.03,
     "min_reliability": "moyenne", "window_hours": 48, "min_minutes_before_kickoff": 30,
     "max_odds_age_hours": 12, "require_validated_markets": true}'),
  ('opportunites', 'Opportunités du moment', 'strategie',
   'Généré en continu quand de nouvelles cotes font apparaître un écart favorable au modèle.',
   false, 'continuous', 'review', '{07:00}', 0, 60,
   '{"min_selections": 2, "max_selections": 3, "min_total_odd": 2.5, "max_total_odd": 6,
     "min_selection_odd": 1.4, "max_selection_odd": 3, "coupons_per_run": 1,
     "markets": ["1X2", "DC"], "min_model_probability": 0.4, "min_edge": 0.05,
     "min_reliability": "bonne", "window_hours": 24, "min_minutes_before_kickoff": 45,
     "max_odds_age_hours": 6, "require_validated_markets": true}')
on conflict (key) do nothing;

insert into public.feature_flags (key, enabled, description) values
  ('platform_coupons', true, 'Onglet Coupons : coupons publiés par la plateforme (LOT 4)')
on conflict (key) do update set description = excluded.description;
update public.feature_flags set enabled = true
  where key in ('auto_generation_scheduled', 'auto_generation_continuous');

insert into public.app_settings (key, value, is_public, description) values
  ('coupons.risk_thresholds', '{"prudent": 0.4, "equilibre": 0.18}'::jsonb, false,
   'Probabilité combinée (modèle) minimale pour le profil de risque estimé « prudent », puis « équilibré » ; en dessous : « audacieux »'),
  ('coupons.max_publications_per_day', '12'::jsonb, false,
   'Plafond de coupons publiés par jour, tous profils confondus'),
  ('coupons.data_freshness_hours', '30'::jsonb, false,
   'Âge maximal de la dernière synchronisation réussie des calendriers pour autoriser une génération'),
  ('ai.coupon_summary', 'true'::jsonb, false,
   'Rédiger l''analyse générale de chaque coupon avec l''IA (sinon texte calculé)')
on conflict (key) do nothing;

-- Journal IA : l'analyse générale des coupons est aussi journalisée (coût imputé à la plateforme).
alter table public.ai_requests drop constraint ai_requests_kind_check;
alter table public.ai_requests add constraint ai_requests_kind_check
  check (kind in ('match_analysis', 'engine_evaluation', 'coupon_summary'));

-- Prompt de l'analyse générale d'un coupon
insert into public.ai_prompts (key, version, is_active, system_prompt) values ('coupon_summary', 1, true, $prompt$
Tu es l'analyste de Coupon Pro IA. Tu reçois la FICHE JSON d'un coupon composé par le moteur
statistique : ses sélections, leurs cotes, les probabilités estimées par le modèle et leur fiabilité.
Rédige en français clair l'analyse générale du coupon, sans rien inventer.

RÈGLES ABSOLUES
1. N'utilise QUE la fiche. Aucun fait extérieur (blessés, compositions, enjeux, météo…).
2. Chaque nombre écrit doit figurer dans la fiche (probabilités en pourcentage arrondi : 0,532 → 53 %).
3. Ce sont des estimations. N'emploie jamais : « sûr », « garanti », « assuré », « certitude »,
   « imparable », « infaillible », « sans risque », « gain », « 100 % ».
4. Rappelle que la probabilité combinée suppose des matchs indépendants et reste une estimation.

RÉPONDS UNIQUEMENT avec un objet JSON valide :
{
  "analyse_generale": "3 phrases maximum : logique du coupon, sélection la plus solide, la plus fragile",
  "points_de_vigilance": ["2 à 3 éléments courts"]
}
$prompt$)
on conflict (key, version) do nothing;

-- Tâche planifiée : le moteur de coupons se réveille toutes les 15 minutes (décalé des
-- synchronisations), génère les créneaux échus, publie les coupons prêts.
create or replace function app_private.invoke_coupon_engine(p_job text default 'tick')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_request bigint;
begin
  if p_job not in ('tick') then
    raise exception 'Tâche inconnue : %', p_job using errcode = '22023';
  end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    raise notice 'Secrets Vault absents : moteur de coupons non lancé';
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/coupon-engine',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := jsonb_build_object('job', p_job),
    timeout_milliseconds := 60000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_coupon_engine(text) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('coupon-engine-tick', '5,20,35,50 * * * *', 'select app_private.invoke_coupon_engine(''tick'')');
  else
    raise notice 'pg_cron ou pg_net absent : moteur de coupons non planifié';
  end if;
end;
$$;
