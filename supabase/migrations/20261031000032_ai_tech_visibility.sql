-- =============================================================================
-- Coupon Pro IA — Détails techniques de l'IA réservés au super administrateur
-- (proposition validée le 31/10, section 3)
--
-- Les utilisateurs voient « Analyse rédigée par l'IA à partir de données vérifiées » ;
-- le fournisseur, le modèle et la version du prompt ne leur sont plus transmis par le
-- serveur (masquage réel, pas seulement à l'écran). Seule la permission ai.providers,
-- donnée au super administrateur, y donne accès.
-- =============================================================================

insert into public.permissions (id, description) values
  ('ai.providers', 'Choisir les fournisseurs d''IA et voir les détails techniques des analyses (super administrateur)')
on conflict (id) do update set description = excluded.description;

-- Le super administrateur possède toutes les permissions (règle de la migration de référence).
insert into public.role_permissions (role_id, permission_id) values ('super_admin', 'ai.providers')
on conflict do nothing;

-- Analyses de match : lecture colonne par colonne, sans fournisseur, modèle ni prompt.
revoke select on public.match_analyses from anon, authenticated;
grant select (id, match_id, engine_version, status, status_reason, stats, analysis,
              source_updated_at, created_at)
  on public.match_analyses to authenticated;

-- Détails techniques d'une analyse : super administrateur uniquement.
create or replace function public.analysis_tech(p_analysis_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not app_private.has_permission((select auth.uid()), 'ai.providers') then
    raise exception 'Action réservée au super administrateur' using errcode = '42501';
  end if;
  select jsonb_build_object(
           'provider', a.provider, 'model', a.model, 'engine_version', a.engine_version,
           'prompt_key', a.prompt_key, 'prompt_version', a.prompt_version,
           'latency_ms', (select r.latency_ms from public.ai_requests r
                          where r.match_id = a.match_id and r.kind = 'match_analysis'
                            and r.created_at <= a.created_at + interval '1 minute'
                          order by r.created_at desc limit 1))
    into v
  from public.match_analyses a where a.id = p_analysis_id;
  return v;
end;
$$;
revoke all on function public.analysis_tech(bigint) from public, anon;
grant execute on function public.analysis_tech(bigint) to authenticated;

-- Analyses des coupons de la plateforme : sans fournisseur ni modèle pour les utilisateurs.
create or replace function public.coupon_analyses(p_ids uuid[])
returns table (id uuid, analysis jsonb, locked boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         case when not v.visible then jsonb_build_object('source', c.analysis ->> 'source')
              when t.tech then c.analysis
              else c.analysis - 'ai_provider' - 'ai_model' end,
         not v.visible
  from public.coupons c
  cross join lateral (select app_private.can_see_coupon_selections((select auth.uid()), c.category, c.first_kickoff_at) as visible) v
  cross join (select app_private.has_permission((select auth.uid()), 'ai.providers') as tech) t
  where c.id = any(p_ids)
    and cardinality(p_ids) <= 200
    -- Mêmes lignes que la politique de lecture des coupons
    and (c.status in ('published', 'withdrawn') or app_private.has_permission((select auth.uid()), 'generation.manage'));
$$;
revoke all on function public.coupon_analyses(uuid[]) from public, anon;
grant execute on function public.coupon_analyses(uuid[]) to authenticated;
