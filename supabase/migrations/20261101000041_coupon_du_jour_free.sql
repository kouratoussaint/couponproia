-- 01/11 (soir) : le Coupon du jour est gratuit pour tous les forfaits, FREE compris, à tout moment.
-- Règle inscrite dans le contrôle d'accès (indépendante des réglages des forfaits).
create or replace function app_private.can_see_coupon(p_user uuid, p_category text, p_first_kickoff timestamptz,
                                                      p_last_kickoff timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_category = 'du_jour'
      or coalesce(p_last_kickoff, p_first_kickoff) + interval '2 hours 15 minutes' <= now()
      or app_private.has_permission(p_user, 'generation.manage')
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') = '"all"'::jsonb
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') ? p_category;
$$;

-- Réglage du forfait FREE aligné (affichage cohérent dans la console).
update public.app_settings
   set value = (select jsonb_agg(case when p ->> 'code' = 'FREE'
                                      then jsonb_set(p, '{features,coupon_categories}', '["du_jour"]'::jsonb) else p end)
                from jsonb_array_elements(value) p)
 where key = 'pricing.plans';
