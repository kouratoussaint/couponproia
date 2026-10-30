-- =============================================================================
-- Coupon Pro IA — LOT 6 — Laboratoire IA et générateur manuel
-- Les outils (construction manuelle, analyse, optimisation, comparaison, simulation) sont
-- calculés par la fonction serveur « lab » et ne consomment pas de crédit (aucun appel IA).
-- =============================================================================
update public.feature_flags set enabled = true where key = 'ai_lab';
