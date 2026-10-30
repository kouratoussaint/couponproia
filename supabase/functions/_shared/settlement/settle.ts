// Règles de règlement (centralisées, pures, testées).
//
// - Les marchés suivis se règlent sur le score à la fin du temps réglementaire (90 minutes et
//   temps additionnel), jamais sur les prolongations ni les tirs au but.
// - Match terminé : gagné ou perdu selon l'issue.
// - Match annulé, abandonné ou attribué sur tapis vert : sélection annulée (void, cote 1,00).
// - Match reporté ou interrompu : en attente, puis annulée s'il n'est pas joué 48 h après
//   l'horaire initial.
// - Coupon : perdu dès qu'une sélection est perdue ; gagné si toutes les sélections restantes
//   sont gagnées (les sélections annulées comptent pour 1,00) ; annulé si toutes sont annulées.

export type SelectionResult = "won" | "lost" | "void" | "pending";
export type CouponResult = "won" | "lost" | "void" | "pending";

export interface MatchState {
  status: string;
  statusShort: string | null;
  kickoffAt: string;
  homeGoals: number | null;
  awayGoals: number | null;
  ftHomeGoals: number | null;
  ftAwayGoals: number | null;
}

export const VOID_AFTER_HOURS = 48;

/** Score à 90 minutes, s'il est connu avec certitude. */
export function regulationScore(m: MatchState): [number, number] | null {
  if (m.ftHomeGoals !== null && m.ftAwayGoals !== null) return [m.ftHomeGoals, m.ftAwayGoals];
  // Sans score à 90 min explicite : le score final ne vaut que pour un match fini sans prolongation.
  if (m.statusShort === "FT" && m.homeGoals !== null && m.awayGoals !== null) return [m.homeGoals, m.awayGoals];
  return null;
}

/** Issue d'une sélection (« 1X2.HOME », « DC.1X », « OU.OVER.2.5 », « BTTS.YES ») sur un score. */
export function outcomeWins(key: string, home: number, away: number): boolean | null {
  const [market, outcome, ...rest] = key.split(".");
  switch (market) {
    case "1X2":
      return outcome === "HOME" ? home > away : outcome === "AWAY" ? away > home : outcome === "DRAW" ? home === away : null;
    case "DC":
      return outcome === "1X" ? home >= away : outcome === "X2" ? away >= home : outcome === "12" ? home !== away : null;
    case "OU": {
      const line = Number(rest.join("."));
      if (!Number.isFinite(line)) return null;
      return outcome === "OVER" ? home + away > line : outcome === "UNDER" ? home + away < line : null;
    }
    case "BTTS":
      return outcome === "YES" ? home > 0 && away > 0 : outcome === "NO" ? home === 0 || away === 0 : null;
  }
  return null;
}

export function selectionResult(key: string, m: MatchState, now: Date): SelectionResult {
  if (["cancelled", "abandoned", "awarded"].includes(m.status)) return "void";
  if (m.status === "postponed" || m.status === "interrupted") {
    return now.getTime() - Date.parse(m.kickoffAt) > VOID_AFTER_HOURS * 3600_000 ? "void" : "pending";
  }
  if (m.status !== "finished") return "pending";
  const score = regulationScore(m);
  if (!score) return "pending";
  const wins = outcomeWins(key, score[0], score[1]);
  return wins === null ? "void" : wins ? "won" : "lost";
}

export function couponResult(selections: { result: SelectionResult; odd: number }[]): { result: CouponResult; settledOdd: number | null } {
  if (selections.some((s) => s.result === "lost")) return { result: "lost", settledOdd: 0 };
  if (selections.some((s) => s.result === "pending")) return { result: "pending", settledOdd: null };
  if (selections.every((s) => s.result === "void")) return { result: "void", settledOdd: 1 };
  const odd = selections.reduce((p, s) => p * (s.result === "void" ? 1 : s.odd), 1);
  return { result: "won", settledOdd: Math.round(odd * 100) / 100 };
}
