-- LOT 11 (3/3) : gestion commerciale.
--  - Codes promo : réduction en pourcentage, appliquée par le serveur au moment du paiement,
--    comptée une seule fois par utilisateur quand le paiement est confirmé et exécuté.
--  - Remboursement enregistré : le remboursement d'argent se fait chez l'agrégateur (CinetPay) ;
--    l'administrateur l'enregistre ici, ce qui retire les droits accordés et trace l'opération.

-- -----------------------------------------------------------------------------
-- Codes promo
-- -----------------------------------------------------------------------------
create table public.promo_codes (
  code         text primary key check (code ~ '^[A-Z0-9_-]{3,24}$'),
  description  text not null default '' check (char_length(description) <= 200),
  percent_off  integer not null check (percent_off between 1 and 90),
  applies_to   text not null default 'all' check (applies_to in ('all', 'subscription', 'credits')),
  -- Forfaits concernés (abonnements) ; vide = tous les forfaits payants.
  plan_codes   text[] not null default '{}',
  starts_at    timestamptz,
  ends_at      timestamptz,
  max_uses     integer check (max_uses is null or max_uses > 0),
  uses         integer not null default 0 check (uses >= 0),
  active       boolean not null default true,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create trigger promo_codes_set_updated_at before update on public.promo_codes
  for each row execute function app_private.set_updated_at();

create table public.promo_redemptions (
  id            bigint generated always as identity primary key,
  code          text not null references public.promo_codes(code) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  payment_id    uuid not null unique references public.payments(id) on delete cascade,
  discount_xof  integer not null check (discount_xof >= 0),
  created_at    timestamptz not null default now(),
  unique (code, user_id)
);

alter table public.promo_codes enable row level security;
alter table public.promo_redemptions enable row level security;
-- Accès uniquement par les fonctions ci-dessous.
revoke all on public.promo_codes, public.promo_redemptions from anon, authenticated;

-- -----------------------------------------------------------------------------
-- Paiements : code appliqué, remboursement
-- -----------------------------------------------------------------------------
alter table public.payments
  add column promo_code     text references public.promo_codes(code) on delete set null,
  add column discount_xof   integer not null default 0 check (discount_xof >= 0),
  add column refunded_at    timestamptz,
  add column refund_reason  text,
  add column refunded_by    uuid references auth.users(id) on delete set null;

do $$
declare
  v_name text;
begin
  select conname into v_name from pg_constraint
  where conrelid = 'public.payments'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) like '%status%pending%succeeded%';
  if v_name is not null then
    execute format('alter table public.payments drop constraint %I', v_name);
  end if;
end;
$$;
alter table public.payments add constraint payments_status_check
  check (status in ('pending', 'succeeded', 'failed', 'cancelled', 'refunded'));

-- -----------------------------------------------------------------------------
-- Contrôle d'un code (utilisé par l'écran d'achat et par le serveur de paiement)
-- -----------------------------------------------------------------------------
create or replace function app_private.promo_check(p_user uuid, p_code text, p_kind text, p_plan text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  v_promo public.promo_codes;
begin
  select * into v_promo from public.promo_codes where code = v_code;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'unknown');
  end if;
  if not v_promo.active then
    return jsonb_build_object('ok', false, 'reason', 'inactive');
  end if;
  if v_promo.starts_at is not null and now() < v_promo.starts_at then
    return jsonb_build_object('ok', false, 'reason', 'not_started');
  end if;
  if v_promo.ends_at is not null and now() >= v_promo.ends_at then
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  if v_promo.max_uses is not null and v_promo.uses >= v_promo.max_uses then
    return jsonb_build_object('ok', false, 'reason', 'exhausted');
  end if;
  -- p_kind nul : contrôle d'affichage (l'app grise ensuite les offres non concernées).
  if p_kind is not null and (
       p_kind not in ('subscription', 'credits')
       or (v_promo.applies_to <> 'all' and v_promo.applies_to <> p_kind)
       or (p_kind = 'subscription' and cardinality(v_promo.plan_codes) > 0
           and not coalesce(p_plan = any (v_promo.plan_codes), false))) then
    return jsonb_build_object('ok', false, 'reason', 'not_applicable');
  end if;
  if exists (select 1 from public.promo_redemptions r where r.code = v_code and r.user_id = p_user) then
    return jsonb_build_object('ok', false, 'reason', 'already_used');
  end if;
  return jsonb_build_object('ok', true, 'code', v_promo.code, 'percent_off', v_promo.percent_off,
                            'description', v_promo.description, 'applies_to', v_promo.applies_to,
                            'plan_codes', to_jsonb(v_promo.plan_codes), 'ends_at', v_promo.ends_at);
end;
$$;
revoke all on function app_private.promo_check(uuid, text, text, text) from public, anon, authenticated;

-- Pour l'écran d'achat (affichage) ; le prix final reste calculé par le serveur.
create or replace function public.check_promo(p_code text, p_kind text default null, p_plan text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  return app_private.promo_check(auth.uid(), p_code, p_kind, p_plan);
end;
$$;
revoke all on function public.check_promo(text, text, text) from public, anon;
grant execute on function public.check_promo(text, text, text) to authenticated;

create or replace function public.svc_promo_check(p_user uuid, p_code text, p_kind text, p_plan text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.promo_check(p_user, p_code, p_kind, p_plan);
$$;
revoke all on function public.svc_promo_check(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.svc_promo_check(uuid, text, text, text) to service_role;

-- Utilisation comptée quand le paiement est exécuté (une fois par utilisateur et par code).
create or replace function app_private.on_payment_fulfilled_promo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if new.promo_code is not null and old.fulfilled_at is null and new.fulfilled_at is not null then
    insert into public.promo_redemptions (code, user_id, payment_id, discount_xof)
    values (new.promo_code, new.user_id, new.id, new.discount_xof)
    on conflict do nothing;
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      update public.promo_codes set uses = uses + 1 where code = new.promo_code;
    end if;
  end if;
  return new;
end;
$$;
create trigger payments_promo_redemption after update of fulfilled_at on public.payments
  for each row execute function app_private.on_payment_fulfilled_promo();

-- -----------------------------------------------------------------------------
-- Administration des codes
-- -----------------------------------------------------------------------------
create or replace function public.admin_promo_codes()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'code', p.code, 'description', p.description, 'percent_off', p.percent_off,
             'applies_to', p.applies_to, 'plan_codes', to_jsonb(p.plan_codes),
             'starts_at', p.starts_at, 'ends_at', p.ends_at, 'max_uses', p.max_uses, 'uses', p.uses,
             'active', p.active, 'created_at', p.created_at,
             'discount_total_xof', (select coalesce(sum(r.discount_xof), 0) from public.promo_redemptions r where r.code = p.code))
           order by p.active desc, p.created_at desc)
    from public.promo_codes p), '[]'::jsonb);
end;
$$;

create or replace function public.admin_save_promo(
  p_code text, p_description text, p_percent integer, p_applies_to text, p_plan_codes text[],
  p_starts timestamptz, p_ends timestamptz, p_max_uses integer, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code, '')));
  v_plan text;
  v_row public.promo_codes;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if v_code !~ '^[A-Z0-9_-]{3,24}$' then
    raise exception 'Code : 3 à 24 caractères (lettres, chiffres, - ou _)' using errcode = '22023';
  end if;
  if p_percent is null or p_percent not between 1 and 90 then
    raise exception 'Réduction entre 1 et 90 %%' using errcode = '22023';
  end if;
  if coalesce(p_applies_to, '') not in ('all', 'subscription', 'credits') then
    raise exception 'Portée invalide' using errcode = '22023';
  end if;
  if p_starts is not null and p_ends is not null and p_ends <= p_starts then
    raise exception 'La fin doit suivre le début' using errcode = '22023';
  end if;
  if p_max_uses is not null and p_max_uses < 1 then
    raise exception 'Nombre d''utilisations invalide' using errcode = '22023';
  end if;
  if app_private.has_forbidden_words(coalesce(p_description, '')) then
    raise exception 'Description : vocabulaire interdit' using errcode = '22023';
  end if;
  foreach v_plan in array coalesce(p_plan_codes, '{}') loop
    if v_plan = 'FREE' or app_private.plan_features(v_plan) = '{}'::jsonb then
      raise exception 'Forfait inconnu : %', v_plan using errcode = '22023';
    end if;
  end loop;

  insert into public.promo_codes as p (code, description, percent_off, applies_to, plan_codes,
                                       starts_at, ends_at, max_uses, active, created_by)
  values (v_code, coalesce(trim(p_description), ''), p_percent, p_applies_to, coalesce(p_plan_codes, '{}'),
          p_starts, p_ends, p_max_uses, coalesce(p_active, true), v_actor)
  on conflict (code) do update set
    description = excluded.description, percent_off = excluded.percent_off, applies_to = excluded.applies_to,
    plan_codes = excluded.plan_codes, starts_at = excluded.starts_at, ends_at = excluded.ends_at,
    max_uses = excluded.max_uses, active = excluded.active
  returning * into v_row;

  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'promo.save', 'promo_code', v_code,
          jsonb_build_object('percent_off', p_percent, 'applies_to', p_applies_to, 'plans', p_plan_codes,
                             'starts_at', p_starts, 'ends_at', p_ends, 'max_uses', p_max_uses, 'active', v_row.active));
  return to_jsonb(v_row);
end;
$$;

-- -----------------------------------------------------------------------------
-- Remboursement enregistré
-- -----------------------------------------------------------------------------
create or replace function public.admin_refund_payment(p_payment uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_pay public.payments;
  v_sub public.subscriptions;
  v_acc public.credit_accounts;
  v_removed integer := 0;
  v_sub_action text;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Motif obligatoire' using errcode = '22023';
  end if;
  select * into v_pay from public.payments where id = p_payment for update;
  if not found then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  if v_pay.status <> 'succeeded' then
    raise exception 'Seul un paiement confirmé peut être remboursé (statut : %)', v_pay.status using errcode = '22023';
  end if;

  if v_pay.fulfilled_at is not null then
    if v_pay.kind = 'subscription' then
      select * into v_sub from public.subscriptions where payment_id = v_pay.id for update;
      if found then
        if v_sub.period_start >= now() then
          delete from public.subscriptions where id = v_sub.id;
          v_sub_action := 'supprimé (pas encore commencé)';
        elsif v_sub.period_end > now() then
          update public.subscriptions set period_end = now(),
                 note = concat_ws(' · ', note, 'remboursé : ' || trim(p_reason))
            where id = v_sub.id;
          v_sub_action := 'arrêté maintenant';
        else
          v_sub_action := 'déjà terminé';
        end if;
      end if;
      perform app_private.refresh_plan_credits(v_pay.user_id);
    else
      v_acc := app_private.refresh_plan_credits(v_pay.user_id);
      -- Les crédits déjà utilisés ne peuvent pas être repris : on retire ce qui reste.
      v_removed := least(coalesce(v_pay.credits, 0), v_acc.extra_credits);
      if v_removed > 0 then
        update public.credit_accounts set extra_credits = extra_credits - v_removed, updated_at = now()
          where user_id = v_pay.user_id returning * into v_acc;
        insert into public.credit_ledger (user_id, delta, bucket, reason, operation_id, kind, balance_after, details, actor_id)
        values (v_pay.user_id, -v_removed, 'extra', 'admin_adjust', v_pay.id, 'refund',
                v_acc.plan_credits + v_acc.extra_credits,
                jsonb_build_object('payment', v_pay.transaction_id, 'reason', trim(p_reason)), v_actor);
      end if;
    end if;
  end if;

  update public.payments set status = 'refunded', refunded_at = now(), refund_reason = trim(p_reason),
         refunded_by = v_actor
    where id = v_pay.id;
  insert into public.payment_events (payment_id, source, payload)
  values (v_pay.id, 'admin', jsonb_build_object('action', 'refund', 'reason', trim(p_reason)));
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'payment.refund', 'payment', v_pay.id::text,
          jsonb_build_object('user', v_pay.user_id, 'kind', v_pay.kind, 'amount_xof', v_pay.amount_xof,
                             'transaction', v_pay.transaction_id, 'reason', trim(p_reason),
                             'subscription', v_sub_action, 'credits_removed', v_removed,
                             'credits_already_used', greatest(coalesce(v_pay.credits, 0) - v_removed, 0)));
  return jsonb_build_object('refunded', true, 'subscription', v_sub_action, 'credits_removed', v_removed,
                            'credits_already_used', case when v_pay.kind = 'credits'
                              then greatest(coalesce(v_pay.credits, 0) - v_removed, 0) else 0 end);
end;
$$;

-- Liste des paiements pour la console : code promo et remboursement en plus.
create or replace function public.admin_payments(p_status text default null, p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', y.id, 'user_id', y.user_id, 'email', u.email, 'kind', y.kind, 'plan', y.plan_code,
             'period', y.period, 'credits', y.credits, 'amount_xof', y.amount_xof, 'status', y.status,
             'transaction_id', y.transaction_id, 'created_at', y.created_at, 'fulfilled_at', y.fulfilled_at,
             'promo_code', y.promo_code, 'discount_xof', y.discount_xof,
             'refunded_at', y.refunded_at, 'refund_reason', y.refund_reason)
           order by y.created_at desc)
    from (select * from public.payments where p_status is null or status = p_status
          order by created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 300)) y
    left join auth.users u on u.id = y.user_id), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_promo_codes(),
  public.admin_save_promo(text, text, integer, text, text[], timestamptz, timestamptz, integer, boolean),
  public.admin_refund_payment(uuid, text) from public, anon;
grant execute on function public.admin_promo_codes(),
  public.admin_save_promo(text, text, integer, text, text[], timestamptz, timestamptz, integer, boolean),
  public.admin_refund_payment(uuid, text) to authenticated;
revoke all on function app_private.on_payment_fulfilled_promo() from public, anon, authenticated;
