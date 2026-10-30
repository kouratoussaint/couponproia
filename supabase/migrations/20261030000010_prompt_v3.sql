-- =============================================================================
-- Coupon Pro IA — LOT 4 — Prompt d'analyse v3
-- Retour du premier test réel (Lille – Lyon) : l'IA proposait « victoire Lyon » ET
-- « victoire Lille », justifiées par la seule probabilité. Nouvelles consignes, vérifiées
-- aussi par le serveur : une issue par marché, justification appuyée sur la fiche.
-- =============================================================================
insert into public.ai_prompts (key, version, is_active, system_prompt)
select 'match_analysis', 3, false,
  replace(system_prompt,
    '7. Sois concis : phrases courtes, 3 éléments maximum par liste.',
    '7. "marches_envisageables" : au plus UNE issue par marché (1X2 et double chance comptent comme un'
    || E'\n' || '   seul marché ; plus/moins comme un autre). Ne propose jamais deux issues concurrentes : choisis'
    || E'\n' || '   la mieux étayée. Liste vide si aucune issue ne se détache.'
    || E'\n' || '8. Chaque justification explique POURQUOI avec un élément concret de la fiche (forme, bilan à'
    || E'\n' || '   domicile ou à l''extérieur, buts attendus, classement, confrontations, cote et écart) : ne te'
    || E'\n' || '   contente jamais de répéter la probabilité.'
    || E'\n' || '9. Sois concis : phrases courtes, 3 éléments maximum par liste.')
from public.ai_prompts where key = 'match_analysis' and version = 2
on conflict (key, version) do nothing;

update public.ai_prompts set is_active = false where key = 'match_analysis' and version <> 3;
update public.ai_prompts set is_active = true where key = 'match_analysis' and version = 3;
