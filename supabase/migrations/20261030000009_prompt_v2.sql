-- =============================================================================
-- Coupon Pro IA — LOT 3 — Prompt d'analyse v2
-- Ajout : tenir compte de la qualité mesurée du moteur (engine_quality). La première
-- évaluation (2 210 matchs 2024/25) montre que le moteur bat la référence sur 1/N/2
-- mais pas sur plus/moins de buts ni « les deux marquent » : l'IA ne doit pas les proposer.
-- =============================================================================
insert into public.ai_prompts (key, version, is_active, system_prompt)
select 'match_analysis', 2, false,
  replace(system_prompt,
    '6. Sois concis : phrases courtes, 3 éléments maximum par liste.',
    '6. "engine_quality.beats_baseline" indique, par famille de marchés (1X2 inclut la double chance,'
    || E'\n' || '   OU = plus/moins, BTTS = les deux marquent), si le moteur a fait mieux qu''une simple fréquence'
    || E'\n' || '   sur l''historique. Ne propose JAMAIS un marché dont la famille vaut false ; tu peux citer sa'
    || E'\n' || '   probabilité dans les tendances en précisant qu''elle est peu fiable.'
    || E'\n' || '7. Sois concis : phrases courtes, 3 éléments maximum par liste.')
from public.ai_prompts where key = 'match_analysis' and version = 1
on conflict (key, version) do nothing;

update public.ai_prompts set is_active = false where key = 'match_analysis' and version <> 2;
update public.ai_prompts set is_active = true where key = 'match_analysis' and version = 2;
