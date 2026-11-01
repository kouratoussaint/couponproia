-- =============================================================================
-- Coupon Pro IA — Demandes du 01/11
--  · Analyse offerte : choisie par le super administrateur, sinon automatiquement à l'heure
--    réglée (featured.auto_pick_hour).
--  · Lien vers le bookmaker de l'utilisateur (facultatif, réglable).
--  · Assistant : prompt v2, aucun critère ajouté sans appui dans le message.
-- =============================================================================

insert into public.permissions (id, description) values
  ('featured.manage', 'Choisir le match de l''analyse offerte du jour (super administrateur)')
on conflict (id) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id) values ('super_admin', 'featured.manage')
on conflict do nothing;

alter table public.featured_matches add column if not exists chosen_by uuid references auth.users(id) on delete set null;
comment on column public.featured_matches.chosen_by is 'Super administrateur qui a choisi le match ; null = choix automatique';
create index if not exists featured_matches_chosen_by_idx on public.featured_matches (chosen_by);

insert into public.app_settings (key, value, is_public, description) values
  ('featured.auto_pick_hour', '9'::jsonb, false,
   'Heure locale (0 à 23) : sans choix du super administrateur, le match offert du jour est choisi automatiquement à partir de cette heure'),
  ('bookmaker.link', 'null'::jsonb, true,
   'Bouton « Ouvrir mon bookmaker » sous les coupons : {"name": "…", "url": "https://…"} ; null pour le masquer')
on conflict (key) do nothing;

-- Choix du match offert (aujourd'hui ou demain), remplaçable tant que le match retenu n'a pas commencé.
create or replace function public.admin_set_featured(p_match bigint, p_day date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_day date := coalesce(p_day, app_private.local_today());
  v_tz text := coalesce((select value #>> '{}' from public.app_settings where key = 'app.timezone'), 'UTC');
  v_match public.matches;
  v_old bigint;
  v_old_kickoff timestamptz;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'featured.manage') then
    raise exception 'Action réservée au super administrateur' using errcode = '42501';
  end if;
  if v_day not in (app_private.local_today(), app_private.local_today() + 1) then
    raise exception 'Choix possible pour aujourd''hui ou demain' using errcode = '22023';
  end if;
  select * into v_match from public.matches where id = p_match;
  if not found then
    raise exception 'Match introuvable' using errcode = 'P0002';
  end if;
  if v_match.status <> 'scheduled' or v_match.kickoff_at <= now() + interval '30 minutes' then
    raise exception 'Match déjà commencé ou trop proche (30 minutes au moins avant le coup d''envoi)' using errcode = '22023';
  end if;
  if (v_match.kickoff_at at time zone v_tz)::date <> v_day then
    raise exception 'Ce match ne se joue pas ce jour-là' using errcode = '22023';
  end if;
  select f.match_id, m.kickoff_at into v_old, v_old_kickoff
  from public.featured_matches f join public.matches m on m.id = f.match_id where f.day = v_day;
  if v_old is not null and v_old <> p_match and v_old_kickoff <= now() then
    raise exception 'Le match offert du jour a déjà commencé : il ne peut plus être remplacé' using errcode = '22023';
  end if;
  insert into public.featured_matches (day, match_id, chosen_at, chosen_by)
  values (v_day, p_match, now(), v_actor)
  on conflict (day) do update set match_id = excluded.match_id, chosen_at = now(), chosen_by = v_actor;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'featured.choose', 'match', p_match::text, jsonb_build_object('day', v_day, 'previous', v_old));
  return jsonb_build_object('day', v_day, 'match_id', p_match, 'previous', v_old);
end;
$$;
revoke all on function public.admin_set_featured(bigint, date) from public, anon;
grant execute on function public.admin_set_featured(bigint, date) to authenticated;

-- Assistant : compréhension stricte (version 2 du prompt).
update public.ai_prompts set is_active = false where key = 'assistant_intent';
insert into public.ai_prompts (key, version, is_active, system_prompt) values ('assistant_intent', 2, true, $prompt$
Tu es « Mon Assistant IA » de Coupon Pro IA, une application d'aide aux pronostics football.
Tu reçois un objet JSON : le message de l'utilisateur, l'historique récent, le coupon en cours
(s'il existe), la liste des compétitions suivies et la date du jour. Ta seule tâche : comprendre
la demande et la traduire en JSON. Ce n'est PAS toi qui choisis les matchs ni les cotes : le moteur
statistique de l'application les calcule ensuite.

Intentions possibles :
- "creer_coupon" : construire un coupon (avec ou sans critères).
- "variantes" : proposer plusieurs versions différentes (« trois versions », « d'autres propositions »).
- "modifier_coupon" : modifier le coupon en cours (retirer, remplacer les plus fragiles, ajouter).
- "analyser_coupon" : évaluer le coupon en cours (sélections fragiles, risques).
- "analyser_matchs" : repérer les rencontres intéressantes d'une période (« analyse les matchs de demain »).
- "question" : toute autre demande (définition d'un marché, fonctionnement de l'app, salutation…).

RÈGLE ABSOLUE : ne remplis un critère que si le message de l'utilisateur le dit explicitement.
Reprends EXACTEMENT les nombres écrits (3 matchs → 3 ; cote 4 → 4 ; « entre 5 et 8 » → min 5,
max 8). N'ajoute aucun jour, marché, équipe, compétition, niveau de risque ou cote qui n'est pas
dans le message. Une cote « par match » ou « par sélection » va dans cote_selection_*, une cote
du coupon dans cote_totale_*. Si un mot-clé est ambigu, laisse le champ vide plutôt que deviner.

Critères (null ou liste vide si non précisés, ne devine pas) :
- "jour" : "aujourdhui", "demain", "week_end" ou une date "AAAA-MM-JJ".
- "competitions" : noms EXACTS pris dans la liste fournie.
- "equipes" / "exclure_equipes" : équipes à inclure obligatoirement / à exclure.
- "nombre_selections", "cote_totale_cible", "cote_totale_min", "cote_totale_max",
  "cote_selection_min", "cote_selection_max" : nombres.
- "marches" : parmi "1X2", "DC" (double chance), "OU" (plus/moins de buts), "BTTS" (les deux marquent).
- "issues" : issues précises si demandées : "1X2.HOME", "1X2.DRAW", "1X2.AWAY", "DC.1X", "DC.12",
  "DC.X2", "OU.OVER.1.5", "OU.UNDER.2.5" (lignes 0.5 à 3.5), "BTTS.YES", "BTTS.NO".
- "risque" : "prudent", "modere" ou "audacieux".
- "nombre_coupons" : pour des variantes (3 au maximum).
Modification du coupon en cours : "retirer_positions" (numéros), "remplacer_plus_fragiles" (combien),
"ajouter" (combien de sélections en plus).

"reponse" : une phrase courte en français. Pour une "question", la réponse complète (5 phrases au
plus) : explique sans inventer de statistiques ni de pronostic ; pour un pronostic, propose de créer
un coupon. N'emploie jamais « sûr », « garanti », « assuré », « certitude », « sans risque », « gain ».

RÉPONDS UNIQUEMENT avec ce JSON :
{"intent": "...", "criteres": {"jour": null, "competitions": [], "equipes": [], "exclure_equipes": [],
 "nombre_selections": null, "cote_totale_cible": null, "cote_totale_min": null, "cote_totale_max": null,
 "cote_selection_min": null, "cote_selection_max": null, "marches": [], "issues": [], "risque": null,
 "nombre_coupons": null},
 "modification": {"retirer_positions": [], "remplacer_plus_fragiles": 0, "ajouter": 0},
 "reponse": "..."}
$prompt$)
on conflict (key, version) do update set is_active = true, system_prompt = excluded.system_prompt;

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
  elsif jsonb_typeof(p_value) = 'number' and (p_value #>> '{}')::numeric < 0 then
    raise exception 'Valeur négative refusée' using errcode = '22023';
  end if;
  update public.app_settings set value = p_value where key = p_key;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (auth.uid(), 'settings.update', 'setting', p_key, jsonb_build_object('old', v_old, 'new', p_value));
end;
$$;
