// Qualité mesurée du moteur (dernière évaluation de sa version) : par famille de marchés,
// le moteur fait-il mieux que la référence sur l'historique ?
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { ENGINE_VERSION } from "./poisson.ts";

export interface EngineQuality {
  evaluatedMatches: number;
  beatsBaseline: Record<string, boolean>;
  /** Par compétition (nom) : le moteur bat-il la référence sur 1/N/2 ? (≥ 100 matchs évalués) */
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
    },
    competitions: Object.fromEntries(
      Object.entries((e.details?.per_competition ?? {}) as Record<string, { matches: number; brierModel: number; brierBaseline: number }>)
        .filter(([, m]) => m.matches >= 100)
        .map(([key, m]) => [key.replace(/ \d{4}$/, ""), m.brierModel < m.brierBaseline] as [string, boolean]),
    ),
  };
}
