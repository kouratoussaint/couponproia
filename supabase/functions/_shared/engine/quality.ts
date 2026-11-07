// Qualité mesurée du moteur (dernière évaluation de sa version) : par famille de marchés,
// le moteur fait-il mieux que la référence sur l'historique ?
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { ENGINE_VERSION } from "./poisson.ts";

export interface EngineQuality {
  evaluatedMatches: number;
  beatsBaseline: Record<string, boolean>;
  /** Par compétition (identifiant) : le moteur bat-il la référence sur 1/N/2 ? (≥ 100 matchs évalués) */
  competitions?: Record<string, boolean>;
}

export async function loadEngineQuality(db: SupabaseClient): Promise<EngineQuality | null> {
  const { data: e } = await db.from("engine_evaluations")
    .select("matches_evaluated, brier_model, brier_baseline, details")
    .eq("engine_version", ENGINE_VERSION).order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!e) return null;
  return {
    evaluatedMatches: e.matches_evaluated,
    beatsBaseline: {
      "1X2": Number(e.brier_model) < Number(e.brier_baseline),
      OU: Number(e.details?.over_2_5?.brierModel) < Number(e.details?.over_2_5?.brierBaseline),
      BTTS: Number(e.details?.btts?.brierModel) < Number(e.details?.btts?.brierBaseline),
      // Marchés récents : présents seulement une fois évalués (absents = pas encore évalués,
      // donc hors des coupons de la plateforme).
      ...(e.details?.dnb ? { DNB: Number(e.details.dnb.brierModel) < Number(e.details.dnb.brierBaseline) } : {}),
      ...(e.details?.team_totals
        ? { TT: Number(e.details.team_totals.brierModel) < Number(e.details.team_totals.brierBaseline) }
        : {}),
    },
    competitions: byCompetition((e.details?.per_competition_ids ?? {}) as Record<string, CompetitionScore>),
  };
}

interface CompetitionScore {
  matches: number;
  brierModel: number;
  brierBaseline: number;
}

/**
 * Regroupe les saisons d'une même compétition par identifiant (« 5:2025 », « 5:2026 ») ; ≥ 100 matchs.
 * Les clés de l'ancien format (« Ligue 1 2025 ») sont ignorées : sans nouvelle évaluation, pas de verdict.
 */
export function byCompetition(per: Record<string, CompetitionScore>): Record<string, boolean> {
  const sums = new Map<string, { n: number; model: number; base: number }>();
  for (const [key, m] of Object.entries(per)) {
    const id = /^(\d+):\d{4}$/.exec(key)?.[1];
    if (!id) continue;
    const name = id;
    const acc = sums.get(name) ?? { n: 0, model: 0, base: 0 };
    acc.n += m.matches;
    acc.model += m.brierModel * m.matches;
    acc.base += m.brierBaseline * m.matches;
    sums.set(name, acc);
  }
  return Object.fromEntries(
    [...sums].filter(([, a]) => a.n >= 100).map(([name, a]) => [name, a.model < a.base] as [string, boolean]),
  );
}
