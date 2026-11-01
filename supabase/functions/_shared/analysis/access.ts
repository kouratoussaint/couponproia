// Droit de lancer une nouvelle analyse de match (fonction pure, testée).
/** Forfait payant, crédits disponibles ou compte de l'équipe (crédits illimités). */
export function analysisAllowed(summary: unknown): boolean {
  const s = (summary ?? {}) as { plan?: string; total?: number; unlimited?: boolean };
  return s.unlimited === true || (typeof s.plan === "string" && s.plan !== "FREE") || Number(s.total ?? 0) > 0;
}

/**
 * Accès à une analyse non encore débloquée (règles du 01/11) :
 *  - forfait payant : quota d'analyses par jour, sans crédit ;
 *  - forfait FREE : `cost` crédits par analyse (0 = gratuit), sans quota journalier.
 */
export type AnalysisDecision =
  | { ok: true; source: "plan" | "credit"; cost: number }
  | { ok: false; error: "daily_limit"; limit: number }
  | { ok: false; error: "credits_required"; cost: number };

export function analysisDecision(
  summary: unknown,
  plan: string,
  usedToday: number,
  dailyLimit: number,
  creditCost: number,
): AnalysisDecision {
  const s = (summary ?? {}) as { total?: number; unlimited?: boolean };
  if (s.unlimited === true) return { ok: true, source: "plan", cost: 0 };
  if (plan !== "FREE") {
    return usedToday >= dailyLimit ? { ok: false, error: "daily_limit", limit: dailyLimit } : { ok: true, source: "plan", cost: 0 };
  }
  const cost = Math.max(0, Math.round(creditCost));
  if (cost > 0 && Number(s.total ?? 0) < cost) return { ok: false, error: "credits_required", cost };
  return { ok: true, source: "credit", cost };
}
