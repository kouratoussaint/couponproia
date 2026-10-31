-- =============================================================================
-- Coupon Pro IA — Propositions validées le 31/10
--  1. Choix de l'IA par le super administrateur (écran Fournisseurs d'IA) : quotas
--     restants enregistrés à chaque appel, tests journalisés, réglages ai.* réservés.
--  2. Coupons : mélange modèle / marché et diversification des matchs.
-- =============================================================================

-- Quotas renvoyés par les fournisseurs (en-têtes de limite) à chaque appel.
alter table public.ai_requests add column if not exists quota jsonb;

alter table public.ai_requests drop constraint ai_requests_kind_check;
alter table public.ai_requests add constraint ai_requests_kind_check
  check (kind in ('match_analysis', 'engine_evaluation', 'coupon_summary', 'assistant_intent', 'provider_test'));

insert into public.app_settings (key, value, is_public, description) values
  ('coupons.market_weight', '0.7'::jsonb, false,
   'Part du marché dans la probabilité retenue pour les coupons (0 = modèle seul, 1 = marché seul)'),
  ('coupons.max_match_uses', '2'::jsonb, false,
   'Nombre maximal de coupons en circulation contenant un même match (0 = sans limite)'),
  ('ai.reference_limits', '{"groq": {"requests_per_minute": 30, "requests_per_day": 1000, "tokens_per_day": 200000}}'::jsonb, false,
   'Limites de référence affichées quand le fournisseur ne renvoie pas son quota (offre gratuite)')
on conflict (key) do nothing;

-- Modèle de chaque fournisseur, y compris la principale : changer de principale ne fait
-- plus perdre son modèle.
update public.app_settings s
set value = coalesce(s.value, '{}'::jsonb)
            || jsonb_build_object(coalesce((select value #>> '{}' from public.app_settings where key = 'ai.provider'), 'gemini'),
                                  (select value from public.app_settings where key = 'ai.model'))
where s.key = 'ai.models'
  and (select value from public.app_settings where key = 'ai.model') is not null;

-- Réglages : les réglages IA sont réservés au super administrateur ; bornes des nouveaux réglages.
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
