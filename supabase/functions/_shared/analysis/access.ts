// Droit de lancer une nouvelle analyse de match (fonction pure, testée).
/** Forfait payant, crédits disponibles ou compte de l'équipe (crédits illimités). */
export function analysisAllowed(summary: unknown): boolean {
  const s = (summary ?? {}) as { plan?: string; total?: number; unlimited?: boolean };
  return s.unlimited === true || (typeof s.plan === "string" && s.plan !== "FREE") || Number(s.total ?? 0) > 0;
}
