-- =============================================================================
-- Coupon Pro IA — LOT 9 — Forfaits, abonnements, packs de crédits, paiements
-- Paiement Mobile Money via un agrégateur (CinetPay, décision du 30/10/2026) derrière une
-- interface PaymentProvider. Les droits ne sont accordés qu'après confirmation par le serveur
-- (vérification auprès de l'agrégateur), une seule fois par paiement (idempotent).
-- =============================================================================

-- Avantages de chaque forfait (configurables). « coupon_categories » : catégories de coupons de
-- la plateforme dont les sélections sont visibles AVANT le coup d'envoi (après, tout est public).
update public.app_settings set value = '[
  {"code": "FREE", "name": "FREE", "monthly_xof": 0, "ai_credits": 2,
   "features": {"coupon_categories": ["du_jour"], "match_analyses_per_day": 3}},
  {"code": "STARTER", "name": "STARTER", "monthly_xof": 2000, "ai_credits": 10,
   "features": {"coupon_categories": "all", "match_analyses_per_day": 20}},
  {"code": "PRO_TIPSTER", "name": "PRO TIPSTER", "monthly_xof": 5000, "ai_credits": 50,
   "features": {"coupon_categories": "all", "match_analyses_per_day": 50}},
  {"code": "BUSINESS", "name": "BUSINESS", "monthly_xof": 10000, "ai_credits": 150,
   "features": {"coupon_categories": "all", "match_analyses_per_day": 100}}
]'::jsonb
where key = 'pricing.plans';

insert into public.app_settings (key, value, is_public, description) values
  ('pricing.annual_discount_percent', '15'::jsonb, true,
   'Réduction de l''abonnement annuel par rapport à 12 mois (à confirmer par l''éditeur)'),
  ('pricing.credit_pack_max_quantity', '5'::jsonb, true, 'Packs de crédits achetables en une fois'),
  ('payments.provider', '"cinetpay"'::jsonb, false, 'Agrégateur de paiement actif'),
  ('payments.channels', '"MOBILE_MONEY"'::jsonb, false, 'Moyens proposés par l''agrégateur (MOBILE_MONEY, CREDIT_CARD, ALL)')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Paiements et abonnements
-- -----------------------------------------------------------------------------
create table public.payments (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references auth.users(id) on delete cascade,
  provider                text not null,
  -- Référence envoyée à l'agrégateur (unique, sans caractère spécial)
  transaction_id          text not null unique,
  kind                    text not null check (kind in ('subscription', 'credits')),
  plan_code               text,
  period                  text check (period in ('monthly', 'annual')),
  credits                 integer,
  amount_xof              integer not null check (amount_xof > 0 and amount_xof % 5 = 0),
  currency                text not null default 'XOF',
  status                  text not null default 'pending'
                            check (status in ('pending', 'succeeded', 'failed', 'cancelled')),
  payment_url             text,
  provider_status         text,
  payment_method          text,
  provider_payload        jsonb not null default '{}'::jsonb,
  paid_at                 timestamptz,
  fulfilled_at            timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check ((kind = 'subscription' and plan_code is not null and period is not null) or (kind = 'credits' and credits > 0))
);
create index payments_user_idx on public.payments (user_id, created_at desc);
create index payments_pending_idx on public.payments (created_at) where status = 'pending';
create trigger payments_set_updated_at before update on public.payments
  for each row execute function app_private.set_updated_at();

create table public.payment_events (
  id           bigint generated always as identity primary key,
  payment_id   uuid references public.payments(id) on delete set null,
  source       text not null check (source in ('webhook', 'check', 'return', 'admin')),
  valid_token  boolean,
  payload      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create index payment_events_payment_idx on public.payment_events (payment_id, created_at);

create table public.subscriptions (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  plan_code     text not null,
  period_start  timestamptz not null,
  period_end    timestamptz not null check (period_end > period_start),
  source        text not null check (source in ('payment', 'admin')),
  payment_id    uuid references public.payments(id) on delete set null,
  note          text,
  created_at    timestamptz not null default now()
);
create index subscriptions_user_idx on public.subscriptions (user_id, period_end desc);
create unique index subscriptions_payment_idx on public.subscriptions (payment_id) where payment_id is not null;

revoke all on public.payments, public.payment_events, public.subscriptions from anon, authenticated;
grant select on public.payments, public.subscriptions to authenticated;
alter table public.payments       enable row level security;
alter table public.payment_events enable row level security;
alter table public.subscriptions  enable row level security;
create policy "ses paiements ou gestionnaire" on public.payments for select to authenticated
  using (user_id = (select auth.uid()) or app_private.has_permission((select auth.uid()), 'billing.manage'));
create policy "ses abonnements ou gestionnaire" on public.subscriptions for select to authenticated
  using (user_id = (select auth.uid()) or app_private.has_permission((select auth.uid()), 'billing.manage'));

-- -----------------------------------------------------------------------------
-- Forfait effectif : abonnement en cours, sinon FREE
-- -----------------------------------------------------------------------------
create or replace function app_private.active_subscription(p_user uuid)
returns public.subscriptions
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.subscriptions
  where user_id = p_user and period_start <= now() and period_end > now()
  order by period_end desc limit 1;
$$;

create or replace function app_private.plan_of(p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$ select coalesce((app_private.active_subscription(p_user)).plan_code, 'FREE'); $$;

create or replace function app_private.plan_features(p_plan text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p -> 'features' from public.app_settings s, jsonb_array_elements(s.value) p
                   where s.key = 'pricing.plans' and p ->> 'code' = p_plan), '{}'::jsonb);
$$;

-- La dotation suit le forfait effectif : nouveau mois ou changement de forfait → nouvelle dotation.
create or replace function app_private.refresh_plan_credits(p_user uuid)
returns public.credit_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_acc public.credit_accounts;
  v_period text := to_char(now() at time zone 'UTC', 'YYYY-MM');
  v_plan text := app_private.plan_of(p_user);
  v_grant integer;
begin
  insert into public.credit_accounts (user_id) values (p_user) on conflict (user_id) do nothing;
  select * into v_acc from public.credit_accounts where user_id = p_user for update;
  if v_acc.plan_period is distinct from v_period or v_acc.plan_code is distinct from v_plan then
    select coalesce((p ->> 'ai_credits')::integer, 0) into v_grant
    from public.app_settings s, jsonb_array_elements(s.value) p
    where s.key = 'pricing.plans' and p ->> 'code' = v_plan;
    v_grant := coalesce(v_grant, 0);
    if v_acc.plan_credits > 0 then
      insert into public.credit_ledger (user_id, delta, bucket, reason, balance_after, details)
      values (p_user, -v_acc.plan_credits, 'plan', 'expire_monthly', v_acc.extra_credits,
              jsonb_build_object('period', v_acc.plan_period, 'plan', v_acc.plan_code,
                                 'cause', case when v_acc.plan_period is distinct from v_period then 'nouveau mois' else 'changement de forfait' end));
    end if;
    update public.credit_accounts
      set plan_credits = v_grant, plan_period = v_period, plan_code = v_plan, updated_at = now()
      where user_id = p_user
      returning * into v_acc;
    insert into public.credit_ledger (user_id, delta, bucket, reason, balance_after, details)
    values (p_user, v_grant, 'plan', 'grant_monthly', v_acc.plan_credits + v_acc.extra_credits,
            jsonb_build_object('period', v_period, 'plan', v_plan));
  end if;
  return v_acc;
end;
$$;

-- Ce que l'utilisateur connecté peut faire (affichage ; le serveur contrôle).
create or replace function public.my_entitlements()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_sub public.subscriptions;
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  v_sub := app_private.active_subscription(v_user);
  return jsonb_build_object(
    'plan', coalesce(v_sub.plan_code, 'FREE'),
    'period_end', v_sub.period_end,
    'features', app_private.plan_features(coalesce(v_sub.plan_code, 'FREE')),
    'credits', app_private.credit_summary(v_user));
end;
$$;
revoke all on function public.my_entitlements() from public, anon;
grant execute on function public.my_entitlements() to authenticated;

-- Coupons de la plateforme : avant le coup d'envoi, les sélections ne sont visibles que si
-- la catégorie fait partie du forfait (après le coup d'envoi, tout est public : transparence).
create or replace function app_private.can_see_coupon_selections(p_user uuid, p_category text, p_first_kickoff timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_first_kickoff <= now()
      or app_private.has_permission(p_user, 'generation.manage')
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') = '"all"'::jsonb
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') ? p_category;
$$;

drop policy "sélections des coupons visibles" on public.coupon_selections;
create policy "sélections des coupons visibles selon le forfait" on public.coupon_selections for select to authenticated
  using (exists (
    select 1 from public.coupons c
    where c.id = coupon_id
      and app_private.can_see_coupon_selections((select auth.uid()), c.category, c.first_kickoff_at)));

-- -----------------------------------------------------------------------------
-- Exécution d'un paiement confirmé (idempotente) : abonnement ou crédits.
-- Réservée au serveur (rôle service), appelée après vérification auprès de l'agrégateur.
-- -----------------------------------------------------------------------------
create or replace function public.svc_fulfill_payment(p_payment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pay public.payments;
  v_current public.subscriptions;
  v_start timestamptz;
  v_months integer;
  v_acc public.credit_accounts;
begin
  select * into v_pay from public.payments where id = p_payment for update;
  if not found then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  if v_pay.status <> 'succeeded' then
    raise exception 'Paiement non confirmé (%)', v_pay.status using errcode = '22023';
  end if;
  if v_pay.fulfilled_at is not null then
    return jsonb_build_object('already_fulfilled', true);
  end if;

  if v_pay.kind = 'subscription' then
    v_current := app_private.active_subscription(v_pay.user_id);
    v_months := case v_pay.period when 'annual' then 12 else 1 end;
    -- Même forfait : prolongation à la suite. Autre forfait : il commence tout de suite.
    v_start := case when v_current.plan_code = v_pay.plan_code then v_current.period_end else now() end;
    insert into public.subscriptions (user_id, plan_code, period_start, period_end, source, payment_id)
    values (v_pay.user_id, v_pay.plan_code, v_start, v_start + make_interval(months => v_months), 'payment', v_pay.id);
    perform app_private.refresh_plan_credits(v_pay.user_id);
  else
    v_acc := app_private.refresh_plan_credits(v_pay.user_id);
    update public.credit_accounts set extra_credits = extra_credits + v_pay.credits, updated_at = now()
      where user_id = v_pay.user_id returning * into v_acc;
    insert into public.credit_ledger (user_id, delta, bucket, reason, operation_id, kind, balance_after, details)
    values (v_pay.user_id, v_pay.credits, 'extra', 'purchase', v_pay.id, 'pack', v_acc.plan_credits + v_acc.extra_credits,
            jsonb_build_object('payment', v_pay.transaction_id, 'amount_xof', v_pay.amount_xof));
  end if;
  update public.payments set fulfilled_at = now() where id = v_pay.id;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (null, 'payment.fulfill', 'payment', v_pay.id::text,
          jsonb_build_object('user', v_pay.user_id, 'kind', v_pay.kind, 'plan', v_pay.plan_code, 'credits', v_pay.credits, 'amount_xof', v_pay.amount_xof));
  return jsonb_build_object('fulfilled', true, 'entitlements', app_private.credit_summary(v_pay.user_id));
end;
$$;
revoke all on function public.svc_fulfill_payment(uuid) from public, anon, authenticated;
grant execute on function public.svc_fulfill_payment(uuid) to service_role;

-- Abonnement accordé à la main (paiement hors application, geste commercial), audité.
create or replace function public.admin_grant_subscription(p_user uuid, p_plan text, p_months integer, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_months not between 1 and 24 or coalesce(trim(p_reason), '') = ''
     or app_private.plan_features(p_plan) = '{}'::jsonb then
    raise exception 'Forfait, durée (1 à 24 mois) et motif obligatoires' using errcode = '22023';
  end if;
  insert into public.subscriptions (user_id, plan_code, period_start, period_end, source, note)
  values (p_user, p_plan, now(), now() + make_interval(months => p_months), 'admin', p_reason);
  perform app_private.refresh_plan_credits(p_user);
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'subscription.grant', 'user', p_user::text,
          jsonb_build_object('plan', p_plan, 'months', p_months, 'reason', p_reason));
end;
$$;
revoke all on function public.admin_grant_subscription(uuid, text, integer, text) from public, anon;
grant execute on function public.admin_grant_subscription(uuid, text, integer, text) to authenticated;

update public.feature_flags set enabled = true where key in ('subscriptions', 'payments');

-- Rapprochement des paiements en attente (notification perdue) toutes les 30 minutes.
create or replace function app_private.invoke_payments_reconcile()
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
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'sports_cron_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;
  select net.http_post(
    url := v_url || '/functions/v1/payments',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{"action": "reconcile"}'::jsonb,
    timeout_milliseconds := 60000
  ) into v_request;
  return v_request;
end;
$$;
revoke all on function app_private.invoke_payments_reconcile() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    perform cron.schedule('payments-reconcile', '15,45 * * * *', 'select app_private.invoke_payments_reconcile()');
  end if;
end;
$$;
