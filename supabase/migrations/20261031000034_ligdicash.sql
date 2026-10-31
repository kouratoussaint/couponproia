-- =============================================================================
-- Coupon Pro IA — LigdiCash, agrégateur de paiement prioritaire (31/10)
-- Ordre des agrégateurs réglable dans la console (réglage payments.providers) ; jeton de
-- facture LigdiCash conservé pour relire le statut (pas de signature sur ses notifications).
-- =============================================================================

alter table public.payments add column if not exists provider_ref text;
comment on column public.payments.provider_ref is
  'Référence de l''agrégateur pour relire le statut (jeton de facture LigdiCash) ; jamais montrée aux utilisateurs';

insert into public.app_settings (key, value, is_public, description) values
  ('payments.providers', '["ligdicash", "cinetpay"]'::jsonb, false,
   'Agrégateurs de paiement, par ordre de priorité : le premier dont les clés sont configurées est utilisé, le suivant prend le relais en cas de refus')
on conflict (key) do nothing;

create or replace function public.admin_set_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
begin
  if not app_private.has_permission(auth.uid(), 'settings.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_key like 'ai.%' and not app_private.has_permission(auth.uid(), 'ai.providers') then
    raise exception 'Réglages IA réservés au super administrateur' using errcode = '42501';
  end if;
  select value into v_old from public.app_settings where key = p_key for update;
  if not found then
    raise exception 'Réglage inconnu : %', p_key using errcode = 'P0002';
  end if;
  if p_value is null or (jsonb_typeof(v_old) <> 'null' and jsonb_typeof(p_value) <> 'null'
                         and jsonb_typeof(v_old) <> jsonb_typeof(p_value)) then
    raise exception 'Type attendu : %', jsonb_typeof(v_old) using errcode = '22023';
  end if;
  if p_key = 'pricing.plans' then
    perform app_private.validate_pricing_plans(p_value);
  elsif p_key in ('pricing.annual_discount_percent') and ((p_value #>> '{}')::numeric < 0 or (p_value #>> '{}')::numeric > 90) then
    raise exception 'Remise entre 0 et 90 %%' using errcode = '22023';
  elsif p_key = 'costs.payment_fee_percent' and ((p_value #>> '{}')::numeric < 0 or (p_value #>> '{}')::numeric > 20) then
    raise exception 'Commission entre 0 et 20 %%' using errcode = '22023';
  elsif p_key = 'costs.usd_to_xof' and (p_value #>> '{}')::numeric <= 0 then
    raise exception 'Taux de conversion positif obligatoire' using errcode = '22023';
  elsif p_key = 'costs.fixed_monthly_xof' and exists (
          select 1 from jsonb_each(p_value) e
          where jsonb_typeof(e.value) <> 'number' or (e.value #>> '{}')::numeric < 0 or btrim(e.key) = '') then
    raise exception 'Chaque abonnement : un nom et un montant positif en FCFA' using errcode = '22023';
  elsif p_key = 'legal.editor' and (
          jsonb_typeof(p_value) <> 'object'
          or exists (select 1 from jsonb_each(p_value) e
                     where e.key not in ('name', 'legal_form', 'address', 'country', 'registration')
                        or jsonb_typeof(e.value) <> 'string' or char_length(e.value #>> '{}') > 200)) then
    raise exception 'Éditeur : champs name, legal_form, address, country, registration (texte, 200 caractères maximum)'
      using errcode = '22023';
  elsif p_key = 'app.support_email' and jsonb_typeof(p_value) <> 'null' and (
          jsonb_typeof(p_value) <> 'string'
          or (p_value #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
          or char_length(p_value #>> '{}') > 254) then
    raise exception 'Adresse e-mail du support invalide' using errcode = '22023';
  elsif p_key = 'coupons.market_weight' and ((p_value #>> '{}')::numeric < 0 or (p_value #>> '{}')::numeric > 1) then
    raise exception 'Part du marché entre 0 et 1' using errcode = '22023';
  elsif p_key = 'coupons.max_match_uses' and ((p_value #>> '{}')::numeric not between 0 and 10
                                              or (p_value #>> '{}')::numeric <> round((p_value #>> '{}')::numeric)) then
    raise exception 'Nombre entier entre 0 et 10' using errcode = '22023';
  elsif p_key = 'payments.providers' and (
          jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) = 0
          or exists (select 1 from jsonb_array_elements(p_value) e
                     where jsonb_typeof(e) <> 'string' or (e #>> '{}') not in ('ligdicash', 'cinetpay'))
          or (select count(distinct e #>> '{}') from jsonb_array_elements(p_value) e) <> jsonb_array_length(p_value)) then
    raise exception 'Agrégateurs : liste ordonnée sans doublon parmi ligdicash et cinetpay (au moins un)' using errcode = '22023';
  elsif jsonb_typeof(p_value) = 'number' and (p_value #>> '{}')::numeric < 0 then
    raise exception 'Valeur négative refusée' using errcode = '22023';
  end if;
  update public.app_settings set value = p_value where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), 'settings.update', 'setting', p_key, jsonb_build_object('old', v_old, 'new', p_value));
end;
$$;
revoke all on function public.admin_set_setting(text, jsonb) from public, anon;
grant execute on function public.admin_set_setting(text, jsonb) to authenticated;

-- Les utilisateurs lisent leurs paiements sans les données techniques de l'agrégateur
-- (jeton de facture, réponse brute, lien de paiement).
do $$
declare
  v_cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'payments'
    and column_name not in ('provider_ref', 'provider_payload', 'payment_url');
  revoke select on public.payments from authenticated;
  execute format('grant select (%s) on public.payments to authenticated', v_cols);
end;
$$;

-- Console → Paiements : agrégateur et statut renvoyé, pour chaque paiement.
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
             'transaction_id', y.transaction_id, 'provider', y.provider, 'provider_status', y.provider_status, 'created_at', y.created_at, 'fulfilled_at', y.fulfilled_at,
             'promo_code', y.promo_code, 'discount_xof', y.discount_xof,
             'refunded_at', y.refunded_at, 'refund_reason', y.refund_reason)
           order by y.created_at desc)
    from (select * from public.payments where p_status is null or status = p_status
          order by created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 300)) y
    left join auth.users u on u.id = y.user_id), '[]'::jsonb);
end;
$$;
