-- LOT 11 : console d'administration.
-- Toutes les fonctions vérifient la permission côté serveur : l'interface ne fait qu'afficher.

-- -----------------------------------------------------------------------------
-- Tableau de bord (admin.access), sur une période en jours
-- -----------------------------------------------------------------------------
create or replace function public.admin_dashboard(p_days integer default 7)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 7), 1), 365);
  v_from timestamptz := now() - make_interval(days => least(greatest(coalesce(p_days, 7), 1), 365));
begin
  if not app_private.has_permission(auth.uid(), 'admin.access') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'days', v_days,
    'from', v_from,
    'users', jsonb_build_object(
      'total', (select count(*) from auth.users),
      'new', (select count(*) from auth.users where created_at >= v_from),
      'active', (select count(*) from auth.users u
                 where (to_jsonb(u) ->> 'last_sign_in_at')::timestamptz >= v_from
                    or exists (select 1 from public.ai_requests a where a.user_id = u.id and a.created_at >= v_from)
                    or exists (select 1 from public.assistant_messages m where m.user_id = u.id and m.created_at >= v_from)),
      'suspended', (select count(*) from public.profiles where is_suspended),
      'tipsters', (select count(*) from public.tipster_profiles where status = 'active')),
    'coupons', jsonb_build_object(
      'generated', (select count(*) from public.coupons where created_at >= v_from),
      'published', (select count(*) from public.coupons where published_at >= v_from),
      'won', (select count(*) from public.coupons where result = 'won' and settled_at >= v_from),
      'lost', (select count(*) from public.coupons where result = 'lost' and settled_at >= v_from),
      'withdrawn', (select count(*) from public.coupons where status = 'withdrawn' and updated_at >= v_from),
      'pending_review', (select count(*) from public.coupons where status = 'pending_review'),
      'user_saved', (select count(*) from public.user_coupons where status = 'saved' and created_at >= v_from),
      'tipster_published', (select count(*) from public.user_coupons where published_at >= v_from)),
    'ai', jsonb_build_object(
      'requests', (select count(*) from public.ai_requests where created_at >= v_from),
      'match_analyses', (select count(*) from public.ai_requests where kind = 'match_analysis' and created_at >= v_from),
      'errors', (select count(*) from public.ai_requests where status in ('error', 'rate_limited') and created_at >= v_from),
      'cost_usd', (select round(coalesce(sum(cost_usd), 0), 4) from public.ai_requests where created_at >= v_from),
      'credits_consumed', (select coalesce(-sum(delta), 0) from public.credit_ledger where reason = 'consume' and created_at >= v_from)),
    'billing', jsonb_build_object(
      'active_subscriptions', (select count(*) from public.subscriptions where period_start <= now() and period_end > now()),
      'revenue_xof', (select coalesce(sum(amount_xof), 0) from public.payments where status = 'succeeded' and created_at >= v_from),
      'payments', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
                   from (select status, count(*) n from public.payments where created_at >= v_from group by status) t)),
    'community', jsonb_build_object(
      'posts', (select count(*) from public.posts where created_at >= v_from),
      'comments', (select count(*) from public.comments where created_at >= v_from),
      'open_reports', (select count(*) from public.reports where status = 'open')),
    'data', jsonb_build_object(
      'requests_used', (select coalesce(sum(requests_used), 0) from public.sync_runs where started_at >= v_from),
      'requests_today', (select coalesce(sum(requests_used), 0) from public.sync_runs where started_at >= date_trunc('day', now())),
      'requests_remaining', (select requests_remaining from public.sync_runs where requests_remaining is not null
                             order by started_at desc limit 1),
      'last_sync', (select max(finished_at) from public.sync_runs where status in ('success', 'partial')),
      'failed_syncs', (select count(*) from public.sync_runs where status = 'failed' and started_at >= v_from)),
    'errors', jsonb_build_object(
      'ai', (select count(*) from public.ai_requests where status = 'error' and created_at >= v_from),
      'sync', (select count(*) from public.sync_runs where status = 'failed' and started_at >= v_from),
      'generation', (select count(*) from public.generation_runs where status = 'failed' and started_at >= v_from),
      'payments', (select count(*) from public.payments where status = 'failed' and created_at >= v_from)),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', d::date,
               'new_users', (select count(*) from auth.users where created_at >= d and created_at < d + interval '1 day'),
               'analyses', (select count(*) from public.ai_requests where kind = 'match_analysis' and created_at >= d and created_at < d + interval '1 day'),
               'revenue_xof', (select coalesce(sum(amount_xof), 0) from public.payments where status = 'succeeded' and created_at >= d and created_at < d + interval '1 day'))
             order by d)
      from generate_series(date_trunc('day', now()) - make_interval(days => least(v_days, 30) - 1), date_trunc('day', now()), interval '1 day') d), '[]'::jsonb),
    'computed_at', now());
end;
$$;

-- -----------------------------------------------------------------------------
-- Utilisateurs (users.manage)
-- -----------------------------------------------------------------------------
create or replace function public.admin_users(p_query text default null, p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_q text := nullif(btrim(p_query), '');
begin
  if not app_private.has_permission(auth.uid(), 'users.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x order by x ->> 'created_at' desc)
    from (
      select jsonb_build_object(
        'id', u.id, 'email', u.email, 'display_name', p.display_name, 'created_at', u.created_at,
        'last_sign_in_at', to_jsonb(u) ->> 'last_sign_in_at',
        'suspended', coalesce(p.is_suspended, false),
        'roles', coalesce((select jsonb_agg(r.role_id order by r.role_id) from public.user_roles r where r.user_id = u.id), '[]'::jsonb),
        'plan', app_private.plan_of(u.id)) as x
      from auth.users u left join public.profiles p on p.id = u.id
      where v_q is null or u.email ilike '%' || v_q || '%' or p.display_name ilike '%' || v_q || '%'
         or u.id::text = v_q
      order by u.created_at desc
      limit least(greatest(coalesce(p_limit, 50), 1), 200)) t), '[]'::jsonb);
end;
$$;

create or replace function public.admin_user_detail(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'users.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception 'Utilisateur introuvable' using errcode = 'P0002';
  end if;
  return (
    select jsonb_build_object(
      'id', u.id, 'email', u.email, 'created_at', u.created_at,
      'last_sign_in_at', to_jsonb(u) ->> 'last_sign_in_at',
      'display_name', p.display_name, 'country_code', p.country_code, 'suspended', coalesce(p.is_suspended, false),
      'roles', coalesce((select jsonb_agg(r.role_id order by r.role_id) from public.user_roles r where r.user_id = u.id), '[]'::jsonb),
      'plan', app_private.plan_of(u.id),
      'credits', app_private.credit_summary(u.id),
      'subscriptions', coalesce((select jsonb_agg(jsonb_build_object('plan', s.plan_code, 'start', s.period_start,
                                    'end', s.period_end, 'source', s.source) order by s.period_start desc)
                                 from public.subscriptions s where s.user_id = u.id), '[]'::jsonb),
      'ledger', coalesce((select jsonb_agg(jsonb_build_object('delta', l.delta, 'reason', l.reason, 'kind', l.kind,
                             'balance_after', l.balance_after, 'created_at', l.created_at) order by l.created_at desc)
                          from (select * from public.credit_ledger where user_id = u.id order by created_at desc limit 20) l), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y.id, 'kind', y.kind, 'plan', y.plan_code,
                               'credits', y.credits, 'amount_xof', y.amount_xof, 'status', y.status,
                               'transaction_id', y.transaction_id, 'created_at', y.created_at) order by y.created_at desc)
                            from (select * from public.payments where user_id = u.id order by created_at desc limit 20) y), '[]'::jsonb),
      'activity', jsonb_build_object(
        'analyses_30d', (select count(*) from public.ai_requests where user_id = u.id and kind = 'match_analysis'
                           and created_at >= now() - interval '30 days'),
        'assistant_messages_30d', (select count(*) from public.assistant_messages where user_id = u.id
                                     and created_at >= now() - interval '30 days'),
        'saved_coupons', (select count(*) from public.user_coupons where user_id = u.id and status = 'saved'),
        'published_coupons', (select count(*) from public.user_coupons where user_id = u.id and published_at is not null),
        'posts', (select count(*) from public.posts where author_id = u.id),
        'comments', (select count(*) from public.comments where author_id = u.id),
        'reports_against', (select count(*) from public.reports r where r.target_id = u.id::text
                              or r.target_id in (select id::text from public.posts where author_id = u.id))),
      'tipster', (select jsonb_build_object('handle', t.handle, 'status', t.status) from public.tipster_profiles t where t.user_id = u.id),
      'audit', coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'created_at', a.created_at, 'details', a.details)
                                          order by a.created_at desc)
                         from (select * from public.audit_logs where target_id = u.id::text order by created_at desc limit 20) a), '[]'::jsonb))
    from auth.users u left join public.profiles p on p.id = u.id
    where u.id = p_user);
end;
$$;

-- -----------------------------------------------------------------------------
-- Réglages (settings.manage) : même type que la valeur actuelle, contrôles dédiés
-- -----------------------------------------------------------------------------
create or replace function app_private.validate_pricing_plans(p_value jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  p jsonb;
begin
  if jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) = 0 then
    raise exception 'La grille doit contenir au moins un forfait' using errcode = '22023';
  end if;
  if (select count(distinct x ->> 'code') from jsonb_array_elements(p_value) x) <> jsonb_array_length(p_value) then
    raise exception 'Codes de forfait en double' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(p_value) x where x ->> 'code' = 'FREE') then
    raise exception 'Le forfait FREE est obligatoire' using errcode = '22023';
  end if;
  for p in select * from jsonb_array_elements(p_value) loop
    if coalesce(p ->> 'code', '') !~ '^[A-Z_]{2,20}$' or coalesce(btrim(p ->> 'name'), '') = '' then
      raise exception 'Forfait invalide : code et nom requis' using errcode = '22023';
    end if;
    if jsonb_typeof(p -> 'monthly_xof') <> 'number' or (p ->> 'monthly_xof')::numeric < 0
       or (p ->> 'monthly_xof')::numeric % 5 <> 0 then
      raise exception 'Prix invalide pour % (multiple de 5 FCFA)', p ->> 'code' using errcode = '22023';
    end if;
    if jsonb_typeof(p -> 'ai_credits') <> 'number' or (p ->> 'ai_credits')::numeric < 0 then
      raise exception 'Crédits invalides pour %', p ->> 'code' using errcode = '22023';
    end if;
    if p ? 'features' and jsonb_typeof(p -> 'features') <> 'object' then
      raise exception 'Avantages invalides pour %', p ->> 'code' using errcode = '22023';
    end if;
  end loop;
  if (select (x ->> 'monthly_xof')::numeric from jsonb_array_elements(p_value) x where x ->> 'code' = 'FREE') <> 0 then
    raise exception 'Le forfait FREE doit rester gratuit' using errcode = '22023';
  end if;
end;
$$;

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
  elsif jsonb_typeof(p_value) = 'number' and (p_value #>> '{}')::numeric < 0 then
    raise exception 'Valeur négative refusée' using errcode = '22023';
  end if;
  update public.app_settings set value = p_value where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), 'settings.update', 'setting', p_key, jsonb_build_object('old', v_old, 'new', p_value));
end;
$$;

-- -----------------------------------------------------------------------------
-- Journal d'audit (audit.read), avec le nom de l'auteur
-- -----------------------------------------------------------------------------
create or replace function public.admin_audit(p_limit integer default 100, p_action text default null,
                                              p_before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.has_permission(auth.uid(), 'audit.read') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', a.id, 'action', a.action, 'target_type', a.target_type, 'target_id', a.target_id,
             'details', a.details, 'created_at', a.created_at,
             'actor', coalesce((select p.display_name from public.profiles p where p.id = a.actor_id), 'Système'))
           order by a.created_at desc)
    from (select * from public.audit_logs
          where (p_action is null or action like p_action || '%')
            and (p_before is null or created_at < p_before)
          order by created_at desc
          limit least(greatest(coalesce(p_limit, 100), 1), 300)) a), '[]'::jsonb);
end;
$$;

-- Paiements (billing.manage) avec l'e-mail du client.
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
             'transaction_id', y.transaction_id, 'created_at', y.created_at, 'fulfilled_at', y.fulfilled_at)
           order by y.created_at desc)
    from (select * from public.payments where p_status is null or status = p_status
          order by created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 300)) y
    left join auth.users u on u.id = y.user_id), '[]'::jsonb);
end;
$$;

-- Droits d'administration de l'utilisateur connecté (sections visibles dans la console).
create or replace function public.my_admin_rights()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'access', app_private.has_permission(auth.uid(), 'admin.access'),
    'users', app_private.has_permission(auth.uid(), 'users.manage'),
    'admins', app_private.has_permission(auth.uid(), 'admins.manage'),
    'flags', app_private.has_permission(auth.uid(), 'flags.manage'),
    'settings', app_private.has_permission(auth.uid(), 'settings.manage'),
    'audit', app_private.has_permission(auth.uid(), 'audit.read'),
    'sports', app_private.has_permission(auth.uid(), 'sports.configure'),
    'ai', app_private.has_permission(auth.uid(), 'ai.configure'),
    'generation', app_private.has_permission(auth.uid(), 'generation.manage'),
    'billing', app_private.has_permission(auth.uid(), 'billing.manage'),
    'moderation', app_private.has_permission(auth.uid(), 'moderation.manage'));
$$;

revoke all on function public.admin_dashboard(integer), public.admin_users(text, integer),
  public.admin_user_detail(uuid), public.admin_set_setting(text, jsonb), public.admin_audit(integer, text, timestamptz),
  public.admin_payments(text, integer), public.my_admin_rights() from public, anon;
grant execute on function public.admin_dashboard(integer), public.admin_users(text, integer),
  public.admin_user_detail(uuid), public.admin_set_setting(text, jsonb), public.admin_audit(integer, text, timestamptz),
  public.admin_payments(text, integer), public.my_admin_rights() to authenticated;
revoke all on function app_private.validate_pricing_plans(jsonb) from public, anon, authenticated;
