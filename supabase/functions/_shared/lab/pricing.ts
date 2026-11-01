// Prix d'un calcul du laboratoire (fonction pure, testée).
// La composition manuelle (build) reste gratuite. Avec le forfait FREE, analyser, optimiser,
// comparer et simuler coûtent `cost` crédits ; forfaits payants et équipe : gratuit.
export const PRICED_LAB_ACTIONS = ["analyze", "optimize", "compare", "simulate"] as const;

export type LabDecision = { ok: true; cost: number } | { ok: false; error: "credits_required"; cost: number };

export function labDecision(action: string, summary: unknown, plan: string, creditCost: number): LabDecision {
  if (!(PRICED_LAB_ACTIONS as readonly string[]).includes(action)) return { ok: true, cost: 0 };
  const s = (summary ?? {}) as { total?: number; unlimited?: boolean };
  if (s.unlimited === true || plan !== "FREE") return { ok: true, cost: 0 };
  const cost = Math.max(0, Math.round(Number.isFinite(creditCost) ? creditCost : 1));
  if (cost > 0 && Number(s.total ?? 0) < cost) return { ok: false, error: "credits_required", cost };
  return { ok: true, cost };
}
