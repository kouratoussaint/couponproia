-- Laboratoire (01/11) : il reste visible et la composition manuelle d'un coupon reste gratuite.
-- Avec le forfait FREE, chaque calcul (analyser, optimiser, comparer, simuler) coûte
-- `lab.credit_cost` crédits (1 par défaut, réglable dans la console) ; forfaits payants : gratuit.
-- Les coûts en crédits (analyse, laboratoire, assistant) sont des entiers bornés.

insert into public.app_settings (key, value, is_public, description) values
  ('lab.credit_cost', '1'::jsonb, true,
   'Crédits débités pour un calcul du laboratoire (analyser, optimiser, comparer, simuler) avec le forfait FREE (0 = gratuit)')
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
  elsif p_key = 'featured.auto_pick_hour' and (jsonb_typeof(p_value) <> 'number'
          or (p_value #>> '{}')::numeric not between 0 and 23
          or (p_value #>> '{}')::numeric <> round((p_value #>> '{}')::numeric)) then
    raise exception 'Heure entière entre 0 et 23' using errcode = '22023';
  elsif p_key = 'bookmaker.link' and jsonb_typeof(p_value) <> 'null' and (
          jsonb_typeof(p_value) <> 'object'
          or char_length(coalesce(p_value ->> 'name', '')) not between 1 and 40
          or coalesce(p_value ->> 'url', '') !~ '^https://[^\s]+$'
          or char_length(p_value ->> 'url') > 300) then
    raise exception 'Lien du bookmaker : {"name": "…", "url": "https://…"} ou null' using errcode = '22023';
  elsif p_key = 'simulator.withholding_percent' and (jsonb_typeof(p_value) <> 'number'
          or (p_value #>> '{}')::numeric not between 0 and 50) then
    raise exception 'Prélèvement entre 0 et 50 %%' using errcode = '22023';
  elsif p_key = 'alerts.odds_move_percent' and (jsonb_typeof(p_value) <> 'number'
          or (p_value #>> '{}')::numeric not between 3 and 50
          or (p_value #>> '{}')::numeric <> round((p_value #>> '{}')::numeric)) then
    raise exception 'Seuil entier entre 3 et 50 %%' using errcode = '22023';
  elsif p_key in ('analysis.credit_cost', 'lab.credit_cost', 'assistant.cost_per_action') and (
          jsonb_typeof(p_value) <> 'number'
          or (p_value #>> '{}')::numeric not between (case when p_key = 'assistant.cost_per_action' then 1 else 0 end) and 50
          or (p_value #>> '{}')::numeric <> round((p_value #>> '{}')::numeric)) then
    raise exception 'Coût en crédits : nombre entier entre % et 50',
      case when p_key = 'assistant.cost_per_action' then 1 else 0 end using errcode = '22023';
  elsif jsonb_typeof(p_value) = 'number' and (p_value #>> '{}')::numeric < 0 then
    raise exception 'Valeur négative refusée' using errcode = '22023';
  end if;
  update public.app_settings set value = p_value where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), 'settings.update', 'setting', p_key, jsonb_build_object('old', v_old, 'new', p_value));
end;
$$;

