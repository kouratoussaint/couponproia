-- Nouveaux marchés (D2, 02/11) : remboursé si nul (DNB : 1 ou 2, nul = sélection annulée) et
-- buts de chaque équipe (TTH domicile, TTA extérieur ; lignes 0,5 / 1,5 / 2,5).
-- Ils restent hors des coupons de la plateforme tant que l'évaluation du moteur ne les valide pas.

insert into public.markets (code, label, description, sort) values
  ('DNB', 'Remboursé si nul', 'Victoire d''une équipe ; en cas de match nul, la sélection est annulée', 50),
  ('TTH', 'Buts de l''équipe à domicile', 'Nombre de buts de l''équipe qui reçoit, au-dessus ou au-dessous d''une ligne', 60),
  ('TTA', 'Buts de l''équipe à l''extérieur', 'Nombre de buts de l''équipe qui se déplace, au-dessus ou au-dessous d''une ligne', 70)
on conflict (code) do update set label = excluded.label, description = excluded.description, sort = excluded.sort;

-- Carnet de paris : ces marchés sont acceptés.
create or replace function public.journal_add(p_source_type text, p_source_id text, p_title text, p_stake integer,
                                              p_total_odd numeric, p_legs jsonb, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_first timestamptz;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  if jsonb_typeof(p_legs) <> 'array' or jsonb_array_length(p_legs) not between 1 and 30 then
    raise exception 'Entre 1 et 30 sélections' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_legs) l
             where jsonb_typeof(l) <> 'object'
                or coalesce(l ->> 'key', '') !~ '^(1X2|DC|OU|BTTS|DNB|TTH|TTA)\.[A-Z0-9]+(\.[0-9]+(\.[0-9]+)?)?$'
                or jsonb_typeof(l -> 'odd') <> 'number' or (l ->> 'odd')::numeric not between 1.01 and 1000
                or jsonb_typeof(l -> 'match_id') <> 'number'
                or not exists (select 1 from public.matches m where m.id = (l ->> 'match_id')::bigint)) then
    raise exception 'Sélection invalide' using errcode = '22023';
  end if;
  if (select count(distinct l ->> 'match_id') from jsonb_array_elements(p_legs) l) <> jsonb_array_length(p_legs) then
    raise exception 'Un seul pari par match' using errcode = '22023';
  end if;
  if (select count(*) from public.bet_journal where user_id = v_user and created_at > now() - interval '1 day') >= 100 then
    raise exception 'Limite de 100 ajouts par jour atteinte' using errcode = '54000';
  end if;
  select min(m.kickoff_at) into v_first
  from jsonb_array_elements(p_legs) l join public.matches m on m.id = (l ->> 'match_id')::bigint;

  insert into public.bet_journal (user_id, source_type, source_id, title, stake, total_odd, legs, note, first_kickoff_at)
  values (v_user, p_source_type, p_source_id, btrim(p_title), p_stake, round(p_total_odd, 2),
          (select jsonb_agg(jsonb_build_object('match_id', (l ->> 'match_id')::bigint, 'key', l ->> 'key',
                                               'odd', round((l ->> 'odd')::numeric, 2),
                                               'label', left(coalesce(l ->> 'label', ''), 120),
                                               'match', left(coalesce(l ->> 'match', ''), 120)))
           from jsonb_array_elements(p_legs) l),
          nullif(btrim(p_note), ''), v_first)
  returning id into v_id;
  return v_id;
end;
$$;

-- Cohérence coupon / analyse IA : « remboursé si nul » appartient à la famille du résultat.
create or replace function app_private.ai_contradiction(p_selection text, p_analysis jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_pick text;
  v_sel_set text[];
  v_pick_set text[];
  v_sel_fam text := split_part(p_selection, '.', 1);
begin
  if p_analysis is null or coalesce(p_analysis ->> 'recommandation_possible', 'false') <> 'true' then
    return null;
  end if;
  for v_pick in select e ->> 'cle' from jsonb_array_elements(coalesce(p_analysis -> 'marches_envisageables', '[]'::jsonb)) e
                where e ->> 'cle' is not null loop
    if v_sel_fam in ('1X2', 'DC', 'DNB') and split_part(v_pick, '.', 1) in ('1X2', 'DC') then
      v_sel_set := case p_selection when '1X2.HOME' then '{H}' when '1X2.DRAW' then '{D}' when '1X2.AWAY' then '{A}'
                     when 'DC.1X' then '{H,D}' when 'DC.X2' then '{D,A}' when 'DC.12' then '{H,A}'
                     -- Remboursé si nul : le nul annule la sélection, il ne la fait pas perdre.
                     when 'DNB.HOME' then '{H,D}' when 'DNB.AWAY' then '{D,A}' end;
      v_pick_set := case v_pick when '1X2.HOME' then '{H}' when '1X2.DRAW' then '{D}' when '1X2.AWAY' then '{A}'
                      when 'DC.1X' then '{H,D}' when 'DC.X2' then '{D,A}' when 'DC.12' then '{H,A}' end;
      if v_sel_set is not null and v_pick_set is not null and not (v_pick_set <@ v_sel_set) then
        return v_pick;
      end if;
    elsif v_sel_fam = 'OU' and split_part(v_pick, '.', 1) = 'OU' then
      if split_part(p_selection, '.', 2) <> split_part(v_pick, '.', 2)
         or (split_part(p_selection, '.', 2) = 'OVER'
             and substr(p_selection, 9)::numeric > substr(v_pick, 9)::numeric)
         or (split_part(p_selection, '.', 2) = 'UNDER'
             and substr(p_selection, 10)::numeric < substr(v_pick, 10)::numeric) then
        return v_pick;
      end if;
    elsif v_sel_fam = 'BTTS' and split_part(v_pick, '.', 1) = 'BTTS' and p_selection <> v_pick then
      return v_pick;
    end if;
  end loop;
  return null;
end;
$$;

-- Assistant : version 3 du prompt, avec les nouveaux marchés.
update public.ai_prompts set is_active = false where key = 'assistant_intent';
insert into public.ai_prompts (key, version, is_active, system_prompt) values ('assistant_intent', 3, true, $prompt$
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
- "marches" : parmi "1X2", "DC" (double chance), "OU" (plus/moins de buts), "BTTS" (les deux marquent),
  "DNB" (remboursé si nul), "TTH" (buts de l'équipe à domicile), "TTA" (buts de l'équipe à l'extérieur).
- "issues" : issues précises si demandées : "1X2.HOME", "1X2.DRAW", "1X2.AWAY", "DC.1X", "DC.12",
  "DC.X2", "OU.OVER.1.5", "OU.UNDER.2.5" (lignes 0.5 à 3.5), "BTTS.YES", "BTTS.NO", "DNB.HOME",
  "DNB.AWAY", "TTH.OVER.0.5", "TTA.UNDER.1.5" (buts par équipe : lignes 0.5 à 2.5).
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
