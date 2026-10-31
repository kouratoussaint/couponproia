// Moteur statistique « poisson-2.0 » (candidat, activé seulement s'il fait mieux sur l'historique).
//
// Différences avec poisson-1.1 :
//  1. Tous les matchs de chaque équipe dans la compétition (domicile ET extérieur), avec un
//     avantage du terrain propre à la compétition : environ deux fois plus de données.
//  2. Forces d'attaque et de défense ajustées ensemble (ajustement itératif), en tenant compte
//     de la force des adversaires rencontrés ; rétrécies vers la moyenne avec k matchs fictifs.
//  3. Pondération de la forme récente : un match perd la moitié de son poids tous les
//     `halfLifeDays` jours (les saisons précédentes comptent donc de moins en moins).
//  4. Correction des petits scores (Dixon-Coles, paramètre ρ) : 0-0, 1-0, 0-1 et 1-1.
// Seuls les matchs joués AVANT le coup d'envoi sont utilisés. Fonctions pures.
import {
  marketProbabilities,
  type ModelResult,
  type PlayedMatch,
  reliabilityFor,
  round,
  topScores,
} from "./poisson.ts";

export const ENGINE_VERSION_2 = "poisson-2.0";

export interface Model2Options {
  halfLifeDays: number;
  shrinkK: number;
  rho: number;
  leaguePriorMatches: number;
  priorHomeGoals: number;
  priorAwayGoals: number;
  iterations: number;
  maxGoals: number;
}

export const DEFAULT_OPTIONS_2: Model2Options = {
  halfLifeDays: 120,
  shrinkK: 4,
  rho: -0.06,
  leaguePriorMatches: 20,
  priorHomeGoals: 1.5,
  priorAwayGoals: 1.2,
  iterations: 6,
  maxGoals: 10,
};

const DAY = 86400_000;
const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x));

export interface Strengths {
  homeAvg: number;
  awayAvg: number;
  attack: Map<number, number>;
  defense: Map<number, number>;
  /** Matchs effectifs (poids de saison, sans la décroissance) par équipe, toutes positions. */
  played: Map<number, number>;
}

/**
 * Forces des équipes à une date : moyenne de buts à domicile et à l'extérieur de la
 * compétition, puis attaque et défense de chaque équipe relatives à 1 (la moyenne).
 */
export function fitStrengths(history: PlayedMatch[], at: number, o: Model2Options = DEFAULT_OPTIONS_2): Strengths {
  const rows = history.map((m) => {
    const age = Math.max(0, (at - Date.parse(m.kickoffAt)) / DAY);
    return { m, w: (m.weight ?? 1) * 0.5 ** (age / o.halfLifeDays) };
  });
  let n = 0, sh = 0, sa = 0;
  const played = new Map<number, number>();
  for (const { m, w } of rows) {
    n += w;
    sh += w * m.homeGoals;
    sa += w * m.awayGoals;
    for (const id of [m.homeId, m.awayId]) played.set(id, (played.get(id) ?? 0) + (m.weight ?? 1));
  }
  const p = o.leaguePriorMatches;
  const homeAvg = (sh + p * o.priorHomeGoals) / (n + p);
  const awayAvg = (sa + p * o.priorAwayGoals) / (n + p);
  const c = (homeAvg + awayAvg) / 2;
  const attack = new Map<number, number>();
  const defense = new Map<number, number>();
  for (const id of played.keys()) {
    attack.set(id, 1);
    defense.set(id, 1);
  }
  for (let it = 0; it < o.iterations; it++) {
    const scored = new Map<number, number>(), expScored = new Map<number, number>();
    const conceded = new Map<number, number>(), expConceded = new Map<number, number>();
    const add = (map: Map<number, number>, id: number, v: number) => map.set(id, (map.get(id) ?? 0) + v);
    for (const { m, w } of rows) {
      const ah = attack.get(m.homeId)!, dh = defense.get(m.homeId)!;
      const aa = attack.get(m.awayId)!, da = defense.get(m.awayId)!;
      add(scored, m.homeId, w * m.homeGoals);
      add(expScored, m.homeId, w * homeAvg * da);
      add(scored, m.awayId, w * m.awayGoals);
      add(expScored, m.awayId, w * awayAvg * dh);
      add(conceded, m.homeId, w * m.awayGoals);
      add(expConceded, m.homeId, w * awayAvg * aa);
      add(conceded, m.awayId, w * m.homeGoals);
      add(expConceded, m.awayId, w * homeAvg * ah);
    }
    const k = o.shrinkK * c;
    for (const id of played.keys()) {
      attack.set(id, ((scored.get(id) ?? 0) + k) / ((expScored.get(id) ?? 0) + k));
      defense.set(id, ((conceded.get(id) ?? 0) + k) / ((expConceded.get(id) ?? 0) + k));
    }
  }
  return { homeAvg, awayAvg, attack, defense, played };
}

/** Matrice des scores avec la correction de Dixon-Coles (ρ < 0 : plus de 0-0 et de 1-1). */
export function dixonColesMatrix(lambdaHome: number, lambdaAway: number, rho: number, maxGoals = 10): number[][] {
  const pmf = (l: number) => {
    const out = [Math.exp(-l)];
    for (let i = 1; i <= maxGoals; i++) out.push(out[i - 1] * l / i);
    return out;
  };
  const ph = pmf(lambdaHome), pa = pmf(lambdaAway);
  const tau = (h: number, a: number) => {
    if (h === 0 && a === 0) return 1 - lambdaHome * lambdaAway * rho;
    if (h === 0 && a === 1) return 1 + lambdaHome * rho;
    if (h === 1 && a === 0) return 1 + lambdaAway * rho;
    if (h === 1 && a === 1) return 1 - rho;
    return 1;
  };
  let total = 0;
  const m = ph.map((x, h) =>
    pa.map((y, a) => {
      const v = Math.max(0, x * y * tau(h, a));
      total += v;
      return v;
    })
  );
  return m.map((row) => row.map((v) => v / total));
}

/** Modèle 2.0 pour un match, à partir des forces calculées à sa date. */
export function runModel2FromStrengths(s: Strengths, homeId: number, awayId: number, o: Model2Options = DEFAULT_OPTIONS_2): ModelResult {
  const lambdaHome = clamp(s.homeAvg * (s.attack.get(homeId) ?? 1) * (s.defense.get(awayId) ?? 1), 0.1, 5);
  const lambdaAway = clamp(s.awayAvg * (s.attack.get(awayId) ?? 1) * (s.defense.get(homeId) ?? 1), 0.1, 5);
  const matrix = dixonColesMatrix(lambdaHome, lambdaAway, o.rho, o.maxGoals);
  const homePlayed = s.played.get(homeId) ?? 0;
  const awayPlayed = s.played.get(awayId) ?? 0;
  return {
    lambdaHome: round(lambdaHome, 2),
    lambdaAway: round(lambdaAway, 2),
    leagueHomeAvg: round(s.homeAvg, 2),
    leagueAwayAvg: round(s.awayAvg, 2),
    sample: {
      leagueMatches: [...s.played.values()].reduce((a, b) => a + b, 0) / 2,
      homeTeamHomeMatches: round(homePlayed / 2, 1),
      awayTeamAwayMatches: round(awayPlayed / 2, 1),
    },
    // Même échelle que la v1.1 : la moitié des matchs d'une équipe se jouent à domicile.
    reliability: reliabilityFor(homePlayed / 2, awayPlayed / 2),
    probabilities: marketProbabilities(matrix),
    topScores: topScores(matrix),
  };
}

export function runModel2(
  history: PlayedMatch[],
  homeId: number,
  awayId: number,
  kickoffAt: string,
  o: Model2Options = DEFAULT_OPTIONS_2,
): ModelResult {
  return runModel2FromStrengths(fitStrengths(history, Date.parse(kickoffAt), o), homeId, awayId, o);
}
