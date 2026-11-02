// Cohérence des coupons avec l'analyse IA du match (demande du 01/11) : une sélection n'est
// retenue que si elle passe quand le pronostic de l'IA se réalise. Les marchés que l'IA n'a pas
// tranchés (ex. les buts quand elle se prononce sur le vainqueur) restent possibles.

/** Position de l'IA sur un match : recommandation possible et pronostics (clés « 1X2.AWAY »…). */
export interface AiPosition {
  recommendation: boolean;
  picks: { key: string; justification: string | null }[];
  summary: string | null;
}

/** Lit la position de l'IA dans une analyse enregistrée (match_analyses.analysis), ou null. */
export function aiPositionOf(analysis: unknown): AiPosition | null {
  if (!analysis || typeof analysis !== "object") return null;
  const a = analysis as Record<string, unknown>;
  const raw = Array.isArray(a.marches_envisageables) ? a.marches_envisageables : [];
  const picks = raw
    .map((p) => (p && typeof p === "object" ? p as Record<string, unknown> : null))
    .filter((p): p is Record<string, unknown> => p !== null && typeof p.cle === "string")
    .map((p) => ({ key: String(p.cle), justification: typeof p.justification === "string" ? p.justification : null }));
  return {
    recommendation: a.recommandation_possible === true && picks.length > 0,
    picks,
    summary: typeof a.resume === "string" ? a.resume : typeof a.conclusion === "string" ? a.conclusion : null,
  };
}

const RESULT: Record<string, string[]> = {
  // Remboursé si nul : le nul annule la sélection sans la faire perdre.
  "DNB.HOME": ["H", "D"],
  "DNB.AWAY": ["D", "A"],
  "1X2.HOME": ["H"],
  "1X2.DRAW": ["D"],
  "1X2.AWAY": ["A"],
  "DC.1X": ["H", "D"],
  "DC.X2": ["D", "A"],
  "DC.12": ["H", "A"],
};

type Family = "result" | "goals" | "btts" | null;

export function familyOf(key: string): Family {
  if (key in RESULT) return "result";
  if (/^OU\.(OVER|UNDER)\.\d+(\.\d+)?$/.test(key)) return "goals";
  if (key === "BTTS.YES" || key === "BTTS.NO") return "btts";
  return null;
}

/** La sélection passe-t-elle chaque fois que le pronostic se réalise ? (même famille de marché) */
export function compatible(selection: string, pick: string): boolean {
  const f = familyOf(selection);
  if (f === null || f !== familyOf(pick)) return true;
  if (f === "result") return RESULT[pick].every((o) => RESULT[selection].includes(o));
  if (f === "btts") return selection === pick;
  const [, sDir, ...sl] = selection.split(".");
  const [, pDir, ...pl] = pick.split(".");
  const sLine = Number(sl.join(".")), pLine = Number(pl.join("."));
  if (sDir !== pDir) return false;
  return sDir === "OVER" ? sLine <= pLine : sLine >= pLine;
}

/** Pronostics de l'IA que la sélection contredit (vide = cohérente). */
export function contradictions(selection: string, position: AiPosition | null): string[] {
  if (!position?.recommendation) return [];
  return position.picks.filter((p) => !compatible(selection, p.key)).map((p) => p.key);
}

/** Justification affichée : explication de l'IA (pronostic de la même famille), puis les chiffres. */
export function aiJustification(selection: string, position: AiPosition | null, stats: string): string {
  if (!position?.recommendation) return stats;
  const same = position.picks.find((p) => familyOf(p.key) === familyOf(selection) && p.justification);
  const text = same?.justification ?? position.summary;
  return text ? `Analyse IA : ${text} ${stats}` : stats;
}
