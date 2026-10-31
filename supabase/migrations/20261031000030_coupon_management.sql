-- 1. Correctif : admin_user_detail était déclarée STABLE alors qu'elle lit le solde de crédits par
--    credit_summary, qui peut écrire (dotation du mois). L'API exécute les fonctions STABLE dans une
--    transaction en lecture seule : la fiche utilisateur échouait (HTTP 405). Fonction rendue VOLATILE.
alter function public.admin_user_detail(uuid) volatile;

-- 2. Suppression définitive des coupons RETIRÉS, par l'équipe (permission coupons.publish).
--    Seuls les coupons au statut « withdrawn » peuvent être supprimés : un coupon publié reste
--    immuable et visible, pertes comprises. Chaque suppression laisse une trace complète dans le
--    journal d'audit (contenu du coupon, motif du retrait, motif de la suppression).
--    L'historique des règlements (settlement_history) est conservé.
create or replace function app_private.protect_published_selection()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status text;
begin
  -- Suppression autorisée uniquement par admin_delete_withdrawn_coupons (coupon retiré).
  if tg_op = 'DELETE' and current_setting('app.coupon_purge', true) = 'on' then
    return old;
  end if;
  select status into v_status from public.coupons where id = old.coupon_id;
  if v_status in ('published', 'withdrawn') then
    if tg_op = 'DELETE' then
      raise exception 'Sélection d''un coupon publié : suppression impossible' using errcode = '42501';
    end if;
    if (new.match_id, new.market_code, new.outcome_code, new.line, new.odd, new.odd_best,
        new.model_probability, new.implied_probability, new.edge, new.justification, new.position)
       is distinct from
       (old.match_id, old.market_code, old.outcome_code, old.line, old.odd, old.odd_best,
        old.model_probability, old.implied_probability, old.edge, old.justification, old.position) then
      raise exception 'Sélection d''un coupon publié : contenu immuable' using errcode = '42501';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.admin_delete_withdrawn_coupons(p_ids uuid[], p_reason text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_count integer;
  v_bad integer;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'coupons.publish') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Motif obligatoire' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_ids), 0) not between 1 and 100 then
    raise exception 'Entre 1 et 100 coupons à la fois' using errcode = '22023';
  end if;
  select count(*) into v_bad from unnest(p_ids) i
  where not exists (select 1 from public.coupons c where c.id = i and c.status = 'withdrawn');
  if v_bad > 0 then
    raise exception 'Seuls les coupons retirés peuvent être supprimés (% coupon(s) refusé(s))', v_bad
      using errcode = '22023';
  end if;

  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  select v_actor, 'coupon.delete', 'coupon', c.id::text,
         jsonb_build_object(
           'reason', trim(p_reason),
           'snapshot', jsonb_build_object(
             'title', c.title, 'category', c.category, 'risk_level', c.risk_level,
             'total_odd', c.total_odd, 'combined_probability', c.combined_probability,
             'published_at', c.published_at, 'first_kickoff_at', c.first_kickoff_at,
             'result', c.result, 'engine_version', c.engine_version,
             'withdrawal', (select jsonb_build_object('reason', h.reason, 'at', h.created_at)
                            from public.coupon_status_history h
                            where h.coupon_id = c.id and h.to_status = 'withdrawn'
                            order by h.created_at desc limit 1),
             'selections', (select coalesce(jsonb_agg(jsonb_build_object(
                                'match_id', s.match_id, 'selection', s.selection_key, 'odd', s.odd,
                                'result', s.result) order by s.position), '[]'::jsonb)
                            from public.coupon_selections s where s.coupon_id = c.id)))
  from public.coupons c where c.id = any (p_ids);

  perform set_config('app.coupon_purge', 'on', true);
  delete from public.coupons where id = any (p_ids) and status = 'withdrawn';
  get diagnostics v_count = row_count;
  perform set_config('app.coupon_purge', 'off', true);
  return v_count;
end;
$$;
revoke all on function public.admin_delete_withdrawn_coupons(uuid[], text) from public, anon;
grant execute on function public.admin_delete_withdrawn_coupons(uuid[], text) to authenticated;
