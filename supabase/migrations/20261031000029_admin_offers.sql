-- Offre d'un pack de crédits par l'équipe (geste commercial, partenaire, test), sans paiement.
-- Le contenu du pack vient du réglage pricing.credit_pack, lu par le serveur : l'app n'envoie
-- que le nombre de packs. Crédits ajoutés au solde supplémentaire (n'expire pas), journalisé.

create or replace function public.admin_grant_credit_pack(p_user uuid, p_quantity integer, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_pack jsonb;
  v_per_pack integer;
  v_price integer;
  v_credits integer;
  v_acc public.credit_accounts;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'billing.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Motif obligatoire' using errcode = '22023';
  end if;
  if p_quantity is null or p_quantity not between 1 and 20 then
    raise exception 'Entre 1 et 20 packs' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception 'Utilisateur introuvable' using errcode = 'P0002';
  end if;
  select value into v_pack from public.app_settings where key = 'pricing.credit_pack';
  v_per_pack := coalesce((v_pack ->> 'credits')::integer, 0);
  v_price := coalesce((v_pack ->> 'price_xof')::integer, 0);
  if v_per_pack <= 0 then
    raise exception 'Pack de crédits non configuré (pricing.credit_pack)' using errcode = '22023';
  end if;
  v_credits := v_per_pack * p_quantity;

  v_acc := app_private.refresh_plan_credits(p_user);
  update public.credit_accounts set extra_credits = extra_credits + v_credits, updated_at = now()
    where user_id = p_user returning * into v_acc;
  insert into public.credit_ledger (user_id, delta, bucket, reason, kind, balance_after, details, actor_id)
  values (p_user, v_credits, 'extra', 'admin_adjust', 'pack_offert', v_acc.plan_credits + v_acc.extra_credits,
          jsonb_build_object('packs', p_quantity, 'reason', trim(p_reason)), v_actor);
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'credits.grant_pack', 'user', p_user::text,
          jsonb_build_object('packs', p_quantity, 'credits', v_credits, 'value_xof', v_price * p_quantity,
                             'reason', trim(p_reason)));
  return jsonb_build_object('credits', v_credits, 'entitlements', app_private.credit_summary(p_user));
end;
$$;
revoke all on function public.admin_grant_credit_pack(uuid, integer, text) from public, anon;
grant execute on function public.admin_grant_credit_pack(uuid, integer, text) to authenticated;

-- Identité de l'éditeur et contact du support (formulaire de la console) : contrôlés par le serveur.
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
  elsif jsonb_typeof(p_value) = 'number' and (p_value #>> '{}')::numeric < 0 then
    raise exception 'Valeur négative refusée' using errcode = '22023';
  end if;
  update public.app_settings set value = p_value where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), 'settings.update', 'setting', p_key, jsonb_build_object('old', v_old, 'new', p_value));
end;
$$;
