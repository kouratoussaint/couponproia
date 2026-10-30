-- =============================================================================
-- Coupon Pro IA — LOT 5 — Crédits IA et Mon Assistant IA
-- Crédits : dotation mensuelle du forfait (non cumulable) + crédits supplémentaires
-- (achats au LOT 9, ajustements admin). Débit uniquement après une opération réussie,
-- jamais deux fois pour la même opération ; tout mouvement est journalisé.
-- Assistant : conversations, messages, coupons de l'utilisateur (propositions puis
-- coupons enregistrés). Écritures serveur ; l'utilisateur ne voit que ses données.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Crédits
-- -----------------------------------------------------------------------------
create table public.credit_accounts (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  plan_code      text not null default 'FREE',
  plan_credits   integer not null default 0 check (plan_credits >= 0),
  plan_period    text,
  extra_credits  integer not null default 0 check (extra_credits >= 0),
  updated_at     timestamptz not null default now()
);

create table public.credit_ledger (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users(id) on delete cascade,
  delta          integer not null,
  bucket         text not null check (bucket in ('plan', 'extra', 'none')),
  reason         text not null check (reason in (
                   'grant_monthly', 'expire_monthly', 'consume', 'refund', 'purchase', 'admin_adjust')),
  operation_id   uuid,
  kind           text,
  balance_after  integer not null,
  details        jsonb not null default '{}'::jsonb,
  actor_id       uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now()
);
-- Pas de double débit : une opération n'est débitée qu'une fois.
create unique index credit_ledger_consume_once_idx on public.credit_ledger (operation_id) where reason = 'consume';
create index credit_ledger_user_idx on public.credit_ledger (user_id, created_at desc);

-- Dotation mensuelle du forfait (pricing.plans) ; les crédits du mois précédent expirent.
create or replace function app_private.refresh_plan_credits(p_user uuid)
returns public.credit_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_acc public.credit_accounts;
  v_period text := to_char(now() at time zone 'UTC', 'YYYY-MM');
  v_grant integer;
begin
  insert into public.credit_accounts (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into v_acc from public.credit_accounts where user_id = p_user for update;
  if v_acc.plan_period is distinct from v_period then
    select coalesce((p ->> 'ai_credits')::integer, 0) into v_grant
    from public.app_settings s, jsonb_array_elements(s.value) p
    where s.key = 'pricing.plans' and p ->> 'code' = v_acc.plan_code;
    v_grant := coalesce(v_grant, 0);
    if v_acc.plan_credits > 0 then
      insert into public.credit_ledger (user_id, delta, bucket, reason, balance_after, details)
      values (p_user, -v_acc.plan_credits, 'plan', 'expire_monthly', v_acc.extra_credits,
              jsonb_build_object('period', v_acc.plan_period));
    end if;
    update public.credit_accounts
      set plan_credits = v_grant, plan_period = v_period, updated_at = now()
      where user_id = p_user
      returning * into v_acc;
    insert into public.credit_ledger (user_id, delta, bucket, reason, balance_after, details)
    values (p_user, v_grant, 'plan', 'grant_monthly', v_acc.plan_credits + v_acc.extra_credits,
            jsonb_build_object('period', v_period, 'plan', v_acc.plan_code));
  end if;
  return v_acc;
end;
$$;

create or replace function app_private.credits_exempt(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select (value)::text::boolean from public.app_settings where key = 'credits.staff_unlimited'), false)
         and app_private.has_permission(p_user, 'admin.access');
$$;

create or replace function app_private.credit_summary(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_acc public.credit_accounts := app_private.refresh_plan_credits(p_user);
begin
  return jsonb_build_object(
    'plan', v_acc.plan_code,
    'period', v_acc.plan_period,
    'plan_credits', v_acc.plan_credits,
    'extra_credits', v_acc.extra_credits,
    'total', v_acc.plan_credits + v_acc.extra_credits,
    'unlimited', app_private.credits_exempt(p_user));
end;
$$;

-- Solde de l'utilisateur connecté (déclenche la dotation du mois si besoin).
create or replace function public.my_credits()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  return app_private.credit_summary(auth.uid());
end;
$$;
revoke all on function public.my_credits() from public, anon;
grant execute on function public.my_credits() to authenticated;

-- Débit après succès, idempotent par opération. Réservé au serveur (rôle service).
create or replace function public.svc_consume_credits(p_user uuid, p_operation uuid, p_amount integer, p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_acc public.credit_accounts;
  v_from_plan integer;
  v_from_extra integer;
begin
  if p_amount <= 0 then
    raise exception 'Montant invalide' using errcode = '22023';
  end if;
  if exists (select 1 from public.credit_ledger where operation_id = p_operation and reason = 'consume') then
    return app_private.credit_summary(p_user) || jsonb_build_object('charged', 0, 'already_charged', true);
  end if;
  v_acc := app_private.refresh_plan_credits(p_user);
  if app_private.credits_exempt(p_user) then
    insert into public.credit_ledger (user_id, delta, bucket, reason, operation_id, kind, balance_after, details)
    values (p_user, 0, 'none', 'consume', p_operation, p_kind, v_acc.plan_credits + v_acc.extra_credits,
            jsonb_build_object('exempt', true, 'amount', p_amount));
    return app_private.credit_summary(p_user) || jsonb_build_object('charged', 0);
  end if;
  if v_acc.plan_credits + v_acc.extra_credits < p_amount then
    raise exception 'Crédits insuffisants' using errcode = 'P0001', hint = 'insufficient_credits';
  end if;
  v_from_plan := least(v_acc.plan_credits, p_amount);
  v_from_extra := p_amount - v_from_plan;
  update public.credit_accounts
    set plan_credits = plan_credits - v_from_plan, extra_credits = extra_credits - v_from_extra, updated_at = now()
    where user_id = p_user
    returning * into v_acc;
  insert into public.credit_ledger (user_id, delta, bucket, reason, operation_id, kind, balance_after, details)
  values (p_user, -p_amount, case when v_from_extra > 0 then 'extra' else 'plan' end, 'consume', p_operation, p_kind,
          v_acc.plan_credits + v_acc.extra_credits,
          jsonb_build_object('from_plan', v_from_plan, 'from_extra', v_from_extra));
  return app_private.credit_summary(p_user) || jsonb_build_object('charged', p_amount);
end;
$$;

create or replace function public.svc_credit_summary(p_user uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$ select app_private.credit_summary(p_user); $$;

revoke all on function public.svc_consume_credits(uuid, uuid, integer, text) from public, anon, authenticated;
revoke all on function public.svc_credit_summary(uuid) from public, anon, authenticated;
grant execute on function public.svc_consume_credits(uuid, uuid, integer, text) to service_role;
grant execute on function public.svc_credit_summary(uuid) to service_role;

-- Ajustement manuel (geste commercial, correction) : crédits supplémentaires.
create or replace function public.admin_adjust_credits(p_user uuid, p_delta integer, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_acc public.credit_accounts;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' or p_delta = 0 then
    raise exception 'Motif et montant obligatoires' using errcode = '22023';
  end if;
  v_acc := app_private.refresh_plan_credits(p_user);
  if v_acc.extra_credits + p_delta < 0 then
    raise exception 'Solde supplémentaire insuffisant' using errcode = '22023';
  end if;
  update public.credit_accounts set extra_credits = extra_credits + p_delta, updated_at = now()
    where user_id = p_user returning * into v_acc;
  insert into public.credit_ledger (user_id, delta, bucket, reason, balance_after, details, actor_id)
  values (p_user, p_delta, 'extra', 'admin_adjust', v_acc.plan_credits + v_acc.extra_credits,
          jsonb_build_object('reason', p_reason), v_actor);
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'credits.adjust', 'user', p_user::text, jsonb_build_object('delta', p_delta, 'reason', p_reason));
  return app_private.credit_summary(p_user);
end;
$$;
revoke all on function public.admin_adjust_credits(uuid, integer, text) from public, anon;
grant execute on function public.admin_adjust_credits(uuid, integer, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Assistant : conversations, messages, coupons de l'utilisateur
-- -----------------------------------------------------------------------------
create table public.assistant_conversations (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  title       text not null default 'Nouvelle conversation',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index assistant_conversations_user_idx on public.assistant_conversations (user_id, updated_at desc);

create table public.assistant_messages (
  id               uuid primary key default gen_random_uuid(),
  conversation_id  uuid not null references public.assistant_conversations(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  role             text not null check (role in ('user', 'assistant')),
  content          text not null,
  intent           text,
  payload          jsonb not null default '{}'::jsonb,
  credits_charged  integer not null default 0,
  created_at       timestamptz not null default now()
);
create index assistant_messages_conversation_idx on public.assistant_messages (conversation_id, created_at);
create index assistant_messages_user_day_idx on public.assistant_messages (user_id, created_at desc);

create table public.user_coupons (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references auth.users(id) on delete cascade,
  conversation_id       uuid references public.assistant_conversations(id) on delete set null,
  message_id            uuid references public.assistant_messages(id) on delete set null,
  status                text not null default 'proposal' check (status in ('proposal', 'saved', 'archived')),
  title                 text not null,
  criteria              jsonb not null default '{}'::jsonb,
  total_odd             numeric(9, 2) not null check (total_odd > 1),
  combined_probability  numeric(6, 4) not null,
  implied_probability   numeric(6, 4),
  risk_level            text not null check (risk_level in ('prudent', 'equilibre', 'audacieux')),
  analysis              jsonb not null default '{}'::jsonb,
  engine_version        text not null,
  fingerprint           text not null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index user_coupons_user_idx on public.user_coupons (user_id, status, created_at desc);
create trigger user_coupons_set_updated_at
  before update on public.user_coupons
  for each row execute function app_private.set_updated_at();

create table public.user_coupon_selections (
  id                   bigint generated always as identity primary key,
  coupon_id            uuid not null references public.user_coupons(id) on delete cascade,
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
  unique (coupon_id, match_id),
  unique (coupon_id, position)
);

revoke all on public.credit_accounts, public.credit_ledger, public.assistant_conversations,
  public.assistant_messages, public.user_coupons, public.user_coupon_selections from anon, authenticated;
grant select on public.credit_accounts, public.credit_ledger, public.assistant_conversations,
  public.assistant_messages, public.user_coupons, public.user_coupon_selections to authenticated;
grant delete on public.assistant_conversations, public.user_coupons to authenticated;
grant update (title) on public.assistant_conversations to authenticated;
grant update (title, status) on public.user_coupons to authenticated;

alter table public.credit_accounts          enable row level security;
alter table public.credit_ledger            enable row level security;
alter table public.assistant_conversations  enable row level security;
alter table public.assistant_messages       enable row level security;
alter table public.user_coupons             enable row level security;
alter table public.user_coupon_selections   enable row level security;

create policy "son compte de crédits ou gestionnaire" on public.credit_accounts for select to authenticated
  using (user_id = (select auth.uid()) or app_private.has_permission((select auth.uid()), 'billing.manage'));
create policy "son journal de crédits ou gestionnaire" on public.credit_ledger for select to authenticated
  using (user_id = (select auth.uid()) or app_private.has_permission((select auth.uid()), 'billing.manage'));

create policy "ses conversations" on public.assistant_conversations for select to authenticated
  using (user_id = (select auth.uid()));
create policy "renommer ses conversations" on public.assistant_conversations for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "supprimer ses conversations" on public.assistant_conversations for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "ses messages" on public.assistant_messages for select to authenticated
  using (user_id = (select auth.uid()));

create policy "ses coupons" on public.user_coupons for select to authenticated
  using (user_id = (select auth.uid()));
create policy "enregistrer ou archiver ses coupons" on public.user_coupons for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and status in ('proposal', 'saved', 'archived'));
create policy "supprimer ses coupons" on public.user_coupons for delete to authenticated
  using (user_id = (select auth.uid()));
create policy "sélections de ses coupons" on public.user_coupon_selections for select to authenticated
  using (exists (select 1 from public.user_coupons c where c.id = coupon_id and c.user_id = (select auth.uid())));

-- -----------------------------------------------------------------------------
-- Réglages, drapeau, journal IA
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, is_public, description) values
  ('credits.staff_unlimited', 'true'::jsonb, false,
   'L''équipe (permission admin.access) utilise l''assistant sans débit (mouvements journalisés à 0)'),
  ('assistant.cost_per_action', '1'::jsonb, true,
   'Crédits débités pour une proposition, une modification ou une analyse réussie (les questions simples sont gratuites)'),
  ('assistant.daily_message_limit', '60'::jsonb, false,
   'Messages par utilisateur et par jour (protection contre les abus)')
on conflict (key) do nothing;

update public.feature_flags set enabled = true where key = 'assistant_ia';

alter table public.ai_requests drop constraint ai_requests_kind_check;
alter table public.ai_requests add constraint ai_requests_kind_check
  check (kind in ('match_analysis', 'engine_evaluation', 'coupon_summary', 'assistant_intent'));

-- Prompt : compréhension des demandes de l'assistant
insert into public.ai_prompts (key, version, is_active, system_prompt) values ('assistant_intent', 1, true, $prompt$
Tu es « Mon Assistant IA » de Coupon Pro IA, une application d'aide aux pronostics football.
Tu reçois un objet JSON : le message de l'utilisateur, l'historique récent, le coupon en cours
(s'il existe), la liste des compétitions suivies et la date du jour. Ta seule tâche : comprendre
la demande et la traduire en JSON. Ce n'est PAS toi qui choisis les matchs ni les cotes : le moteur
statistique de l'application les calcule ensuite.

Intentions possibles :
- "creer_coupon" : construire un coupon (avec ou sans critères).
- "variantes" : proposer plusieurs versions différentes (« trois versions », « d'autres propositions »).
- "modifier_coupon" : modifier le coupon en cours (retirer, remplacer les plus fragiles, ajouter).
- "analyser_coupon" : évaluer le coupon en cours (sélections fragiles, risques).
- "analyser_matchs" : repérer les rencontres intéressantes d'une période (« analyse les matchs de demain »).
- "question" : toute autre demande (définition d'un marché, fonctionnement de l'app, salutation…).

Critères (null ou liste vide si non précisés, ne devine pas) :
- "jour" : "aujourdhui", "demain", "week_end" ou une date "AAAA-MM-JJ".
- "competitions" : noms EXACTS pris dans la liste fournie.
- "equipes" / "exclure_equipes" : équipes à inclure obligatoirement / à exclure.
- "nombre_selections", "cote_totale_cible", "cote_totale_min", "cote_totale_max",
  "cote_selection_min", "cote_selection_max" : nombres.
- "marches" : parmi "1X2", "DC" (double chance), "OU" (plus/moins de buts), "BTTS" (les deux marquent).
- "issues" : issues précises si demandées : "1X2.HOME", "1X2.DRAW", "1X2.AWAY", "DC.1X", "DC.12",
  "DC.X2", "OU.OVER.1.5", "OU.UNDER.2.5" (lignes 0.5 à 3.5), "BTTS.YES", "BTTS.NO".
- "risque" : "prudent", "modere" ou "audacieux".
- "nombre_coupons" : pour des variantes (3 au maximum).
Modification du coupon en cours : "retirer_positions" (numéros), "remplacer_plus_fragiles" (combien),
"ajouter" (combien de sélections en plus).

"reponse" : une phrase courte en français. Pour une "question", la réponse complète (5 phrases au
plus) : explique sans inventer de statistiques ni de pronostic ; pour un pronostic, propose de créer
un coupon. N'emploie jamais « sûr », « garanti », « assuré », « certitude », « sans risque », « gain ».

RÉPONDS UNIQUEMENT avec ce JSON :
{"intent": "...", "criteres": {"jour": null, "competitions": [], "equipes": [], "exclure_equipes": [],
 "nombre_selections": null, "cote_totale_cible": null, "cote_totale_min": null, "cote_totale_max": null,
 "cote_selection_min": null, "cote_selection_max": null, "marches": [], "issues": [], "risque": null,
 "nombre_coupons": null},
 "modification": {"retirer_positions": [], "remplacer_plus_fragiles": 0, "ajouter": 0},
 "reponse": "..."}
$prompt$)
on conflict (key, version) do nothing;
