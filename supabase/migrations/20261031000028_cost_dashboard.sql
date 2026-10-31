-- LOT 12 (3/3) : mesure des coûts et coût moyen par utilisateur actif (cahier des charges §24).
-- Mesuré par la plateforme : appels IA (coût estimé par requête), requêtes API sportives,
-- notifications, stockage, taille de la base, commissions de paiement.
-- Renseigné par l'administrateur : abonnements fixes mensuels (hébergement, données, domaine…),
-- taux de commission de l'agrégateur, taux de conversion USD → FCFA.
-- La bande passante n'est pas lisible depuis la base : à consulter dans le tableau de bord Supabase.

insert into public.app_settings (key, value, is_public, description) values
  ('costs.usd_to_xof', '600'::jsonb, false,
   'Taux de conversion USD → FCFA utilisé pour les estimations de coûts (à ajuster).'),
  ('costs.fixed_monthly_xof',
   '{"Supabase": 0, "API-Football": 0, "Nom de domaine et site": 0, "Autres": 0}'::jsonb, false,
   'Abonnements fixes par mois, en FCFA (nom → montant). Répartis sur la période affichée dans « Coûts ».'),
  ('costs.payment_fee_percent', '0'::jsonb, false,
   'Commission de l''agrégateur de paiement, en % du montant encaissé (selon le contrat CinetPay).')
on conflict (key) do nothing;

-- Utilisateur actif : connexion, analyse IA ou message à l'assistant depuis la date donnée.
create or replace function app_private.active_user_count(p_from timestamptz)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*) from auth.users u
  where (to_jsonb(u) ->> 'last_sign_in_at')::timestamptz >= p_from
     or exists (select 1 from public.ai_requests a where a.user_id = u.id and a.created_at >= p_from)
     or exists (select 1 from public.assistant_messages m where m.user_id = u.id and m.created_at >= p_from);
$$;
revoke all on function app_private.active_user_count(timestamptz) from public, anon, authenticated;

create or replace function public.admin_costs(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from timestamptz := now() - make_interval(days => v_days);
  v_rate numeric;
  v_fee_pct numeric;
  v_fixed jsonb;
  v_fixed_month numeric;
  v_fixed_period numeric;
  v_ai_usd numeric;
  v_ai_xof numeric;
  v_revenue numeric;
  v_fees numeric;
  v_active bigint;
  v_total numeric;
  v_files jsonb := '[]'::jsonb;
begin
  if not app_private.has_permission(auth.uid(), 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  select coalesce((value #>> '{}')::numeric, 600) into v_rate from public.app_settings where key = 'costs.usd_to_xof';
  v_rate := coalesce(v_rate, 600);
  select coalesce((value #>> '{}')::numeric, 0) into v_fee_pct from public.app_settings where key = 'costs.payment_fee_percent';
  v_fee_pct := coalesce(v_fee_pct, 0);
  select value into v_fixed from public.app_settings where key = 'costs.fixed_monthly_xof';
  v_fixed := coalesce(v_fixed, '{}'::jsonb);
  select coalesce(sum((e.value #>> '{}')::numeric), 0) into v_fixed_month
  from jsonb_each(v_fixed) e where jsonb_typeof(e.value) = 'number';
  v_fixed_period := round(v_fixed_month * v_days / 30.0);

  select coalesce(sum(cost_usd), 0) into v_ai_usd from public.ai_requests where created_at >= v_from;
  v_ai_xof := round(v_ai_usd * v_rate);
  select coalesce(sum(amount_xof), 0) into v_revenue from public.payments
  where status = 'succeeded' and created_at >= v_from;
  v_fees := round(v_revenue * v_fee_pct / 100);
  v_active := app_private.active_user_count(v_from);
  v_total := v_ai_xof + v_fixed_period + v_fees;
  -- Fichiers par compartiment (schéma storage présent sur Supabase, absent des bases de test).
  if to_regclass('storage.objects') is not null then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object('bucket', bucket_id, 'objects', n, 'bytes', b) order by b desc), '[]'::jsonb)
      from (select bucket_id, count(*) n, coalesce(sum((metadata ->> 'size')::bigint), 0) b
            from storage.objects group by bucket_id) s
    $q$ into v_files;
  end if;

  return jsonb_build_object(
    'days', v_days,
    'from', v_from,
    'usd_to_xof', v_rate,
    'active_users', v_active,
    'revenue_xof', v_revenue,
    'total_xof', v_total,
    'per_active_user_xof', case when v_active > 0 then round(v_total / v_active) end,
    'revenue_per_active_user_xof', case when v_active > 0 then round(v_revenue / v_active) end,
    'margin_xof', v_revenue - v_total,
    'ai', jsonb_build_object(
      'cost_usd', round(v_ai_usd, 4),
      'cost_xof', v_ai_xof,
      'requests', (select count(*) from public.ai_requests where created_at >= v_from),
      'unpriced', (select count(*) from public.ai_requests where created_at >= v_from and cost_usd is null
                     and status not in ('stats_only', 'rate_limited')),
      'by_kind', coalesce((
        select jsonb_agg(jsonb_build_object('kind', kind, 'requests', n, 'cost_usd', round(c, 4)) order by c desc)
        from (select kind, count(*) n, coalesce(sum(cost_usd), 0) c from public.ai_requests
              where created_at >= v_from group by kind) k), '[]'::jsonb)),
    'fixed', jsonb_build_object(
      'monthly_xof', v_fixed_month,
      'period_xof', v_fixed_period,
      'items', v_fixed,
      'configured', v_fixed_month > 0),
    'payments', jsonb_build_object(
      'fee_percent', v_fee_pct,
      'fees_xof', v_fees,
      'count', (select count(*) from public.payments where status = 'succeeded' and created_at >= v_from)),
    'sports', jsonb_build_object(
      'requests', (select coalesce(sum(requests_used), 0) from public.sync_runs where started_at >= v_from),
      'requests_per_day', round((select coalesce(sum(requests_used), 0) from public.sync_runs where started_at >= v_from)::numeric / v_days),
      'remaining_today', (select requests_remaining from public.sync_runs where requests_remaining is not null
                          order by started_at desc limit 1)),
    'notifications', jsonb_build_object(
      'created', (select count(*) from public.notifications where created_at >= v_from),
      'sent', (select count(*) from public.notifications where created_at >= v_from and push_status = 'sent'),
      'failed', (select count(*) from public.notifications where created_at >= v_from and push_status = 'failed')),
    'storage', jsonb_build_object(
      'database_bytes', pg_database_size(current_database()),
      'files', v_files),
    'computed_at', now());
end;
$$;
revoke all on function public.admin_costs(integer) from public, anon;
grant execute on function public.admin_costs(integer) to authenticated;

-- Réglages de coûts : montants positifs, commission plafonnée.
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
  elsif jsonb_typeof(p_value) = 'number' and (p_value #>> '{}')::numeric < 0 then
    raise exception 'Valeur négative refusée' using errcode = '22023';
  end if;
  update public.app_settings set value = p_value where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), 'settings.update', 'setting', p_key, jsonb_build_object('old', v_old, 'new', p_value));
end;
$$;
