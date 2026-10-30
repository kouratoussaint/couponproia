-- LOT 9 (complément) : le contenu d'un coupon réservé ne fuit pas par l'API.
-- Avant le coup d'envoi, un coupon d'une catégorie non incluse dans le forfait ne montre ni ses
-- sélections (politique RLS du LOT 9), ni son analyse (qui cite les matchs et les issues), ni son
-- empreinte (liste des matchs et des issues). Ces deux colonnes ne sont plus lisibles directement ;
-- l'analyse passe par coupon_analyses(), qui applique la même règle que les sélections.

revoke select on public.coupons from authenticated;
grant select (id, profile_id, run_id, source, category, title, description, risk_level, total_odd, combined_probability, implied_probability, status, publish_at, published_at, first_kickoff_at, last_kickoff_at, engine_version, data_source, status_note, result, settled_at, settled_odd, created_at, updated_at) on public.coupons to authenticated;

create or replace function public.coupon_analyses(p_ids uuid[])
returns table (id uuid, analysis jsonb, locked boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         case when v.visible then c.analysis
              else jsonb_build_object('source', c.analysis ->> 'source') end,
         not v.visible
  from public.coupons c
  cross join lateral (select app_private.can_see_coupon_selections((select auth.uid()), c.category, c.first_kickoff_at) as visible) v
  where c.id = any(p_ids)
    and cardinality(p_ids) <= 200
    -- Mêmes lignes que la politique de lecture des coupons
    and (c.status in ('published', 'withdrawn') or app_private.has_permission((select auth.uid()), 'generation.manage'));
$$;
revoke all on function public.coupon_analyses(uuid[]) from public, anon;
grant execute on function public.coupon_analyses(uuid[]) to authenticated;

-- Les statistiques lisent des colonnes explicites (la colonne analysis n'est plus accessible).
create or replace function public.platform_performance(p_days integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select c.id, c.category, c.status, c.total_odd, c.result, c.settled_odd, c.published_at, c.first_kickoff_at
    from public.coupons c
    where c.status = 'published'
      and c.published_at <= c.first_kickoff_at
      and (p_days is null or c.published_at >= now() - make_interval(days => p_days))
  ),
  settled as (select * from base where result in ('won', 'lost')),
  sels as (
    select s.*, c.result as coupon_result, comp.name as competition
    from public.coupon_selections s
    join base c on c.id = s.coupon_id
    join public.matches m on m.id = s.match_id
    join public.competitions comp on comp.id = m.competition_id
  )
  select jsonb_build_object(
    'scope', 'Coupons publiés par la plateforme avant le coup d''envoi' ||
             case when p_days is null then '' else ', ' || p_days || ' derniers jours' end,
    'coupons', (select count(*) from base),
    'won', (select count(*) from base where result = 'won'),
    'lost', (select count(*) from base where result = 'lost'),
    'void', (select count(*) from base where result = 'void'),
    'pending', (select count(*) from base where result is null),
    'withdrawn', (select count(*) from public.coupons where status = 'withdrawn'),
    'win_rate', (select round(count(*) filter (where result = 'won')::numeric / nullif(count(*), 0), 4) from settled),
    'average_odd', (select round(avg(total_odd), 2) from settled),
    'stake_note', 'Mise théorique de 1 unité par coupon (aucun pari réel)',
    'theoretical_return', (select round((coalesce(sum(settled_odd) filter (where result = 'won'), 0) - count(*)) / nullif(count(*), 0), 4) from settled),
    'by_category', coalesce((
      select jsonb_agg(x order by x->>'key') from (
        select jsonb_build_object('key', category, 'coupons', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost'),
          'win_rate', round(count(*) filter (where result = 'won')::numeric / nullif(count(*) filter (where result in ('won', 'lost')), 0), 4),
          'average_odd', round(avg(total_odd), 2)) as x
        from base group by category) t), '[]'::jsonb),
    'by_competition', coalesce((
      select jsonb_agg(x order by (x->>'selections')::int desc) from (
        select jsonb_build_object('key', competition, 'selections', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost'),
          'hit_rate', round(count(*) filter (where result = 'won')::numeric / nullif(count(*) filter (where result in ('won', 'lost')), 0), 4)) as x
        from sels group by competition) t), '[]'::jsonb),
    'by_market', coalesce((
      select jsonb_agg(x order by (x->>'selections')::int desc) from (
        select jsonb_build_object('key', market_code, 'selections', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost'),
          'hit_rate', round(count(*) filter (where result = 'won')::numeric / nullif(count(*) filter (where result in ('won', 'lost')), 0), 4),
          'average_model_probability', round(avg(model_probability), 4)) as x
        from sels group by market_code) t), '[]'::jsonb),
    'by_week', coalesce((
      select jsonb_agg(x order by x->>'week') from (
        select jsonb_build_object('week', to_char(date_trunc('week', published_at), 'YYYY-MM-DD'), 'coupons', count(*),
          'won', count(*) filter (where result = 'won'), 'lost', count(*) filter (where result = 'lost')) as x
        from base group by date_trunc('week', published_at)) t), '[]'::jsonb),
    -- Calibration réelle : probabilité annoncée par le modèle contre taux de réussite constaté.
    'calibration', coalesce((
      select jsonb_agg(x order by x->>'bucket') from (
        select jsonb_build_object('bucket', floor(model_probability * 10) / 10, 'selections', count(*),
          'predicted', round(avg(model_probability), 3),
          'observed', round(count(*) filter (where result = 'won')::numeric / count(*), 3)) as x
        from sels where result in ('won', 'lost') group by floor(model_probability * 10)) t), '[]'::jsonb)
  );
$$;
