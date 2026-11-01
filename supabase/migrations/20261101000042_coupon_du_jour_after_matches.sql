-- 01/11 (correction) : le Coupon du jour n'est PAS accessible au forfait FREE avant les matchs.
-- Retour à la règle de la 0.26.0 : FREE voit chaque coupon 2 h 15 après le coup d'envoi de son
-- dernier match ; les forfaits payants, à tout moment.
create or replace function app_private.can_see_coupon(p_user uuid, p_category text, p_first_kickoff timestamptz,
                                                      p_last_kickoff timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_last_kickoff, p_first_kickoff) + interval '2 hours 15 minutes' <= now()
      or app_private.has_permission(p_user, 'generation.manage')
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') = '"all"'::jsonb
      or (app_private.plan_features(app_private.plan_of(p_user)) -> 'coupon_categories') ? p_category;
$$;

update public.app_settings
   set value = (select jsonb_agg(case when p ->> 'code' = 'FREE'
                                      then jsonb_set(p, '{features,coupon_categories}', '[]'::jsonb) else p end)
                from jsonb_array_elements(value) p)
 where key = 'pricing.plans';
