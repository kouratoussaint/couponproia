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

/**
 * Réglages retenus par le backtest du 31/10 (réglage sur la saison 2025, vérifié sur 2026) :
 * demi-vie de 730 jours, k = 5. La correction de Dixon-Coles (ρ) n'apportait rien de mesurable
 * sur ces données : elle reste disponible mais désactivée (ρ = 0).
 */
export const DEFAULT_OPTIONS_2: Model2Options = {
  halfLifeDays: 730,
  shrinkK: 5,
  rho: 0,
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
  // Équipes indexées dans des tableaux (calcul rejoué pour chaque jour de l'historique).
  const index = new Map<number, number>();
  const ids: number[] = [];
  const idx = (id: number) => {
    let i = index.get(id);
    if (i === undefined) {
      i = ids.length;
      index.set(id, i);
      ids.push(id);
    }
    return i;
  };
  const n = history.length;
  const hi = new Int32Array(n), ai = new Int32Array(n);
  const hg = new Float64Array(n), ag = new Float64Array(n), w = new Float64Array(n);
  let sw = 0, sh = 0, sa = 0;
  const playedRaw: number[] = [];
  for (let r = 0; r < n; r++) {
    const m = history[r];
    const age = Math.max(0, (at - Date.parse(m.kickoffAt)) / DAY);
    w[r] = (m.weight ?? 1) * 0.5 ** (age / o.halfLifeDays);
    hi[r] = idx(m.homeId);
    ai[r] = idx(m.awayId);
    hg[r] = m.homeGoals;
    ag[r] = m.awayGoals;
    sw += w[r];
    sh += w[r] * m.homeGoals;
    sa += w[r] * m.awayGoals;
    for (const t of [hi[r], ai[r]]) playedRaw[t] = (playedRaw[t] ?? 0) + (m.weight ?? 1);
  }
  const p = o.leaguePriorMatches;
  const homeAvg = (sw + p) > 0 ? (sh + p * o.priorHomeGoals) / (sw + p) : o.priorHomeGoals;
  const awayAvg = (sw + p) > 0 ? (sa + p * o.priorAwayGoals) / (sw + p) : o.priorAwayGoals;
  const k = o.shrinkK * (homeAvg + awayAvg) / 2;
  const T = ids.length;
  const att = new Float64Array(T).fill(1), def = new Float64Array(T).fill(1);
  const sc = new Float64Array(T), es = new Float64Array(T), co = new Float64Array(T), ec = new Float64Array(T);
  for (let it = 0; it < o.iterations; it++) {
    sc.fill(0);
    es.fill(0);
    co.fill(0);
    ec.fill(0);
    for (let r = 0; r < n; r++) {
      const h = hi[r], a = ai[r], x = w[r];
      sc[h] += x * hg[r];
      es[h] += x * homeAvg * def[a];
      sc[a] += x * ag[r];
      es[a] += x * awayAvg * def[h];
      co[h] += x * ag[r];
      ec[h] += x * awayAvg * att[a];
      co[a] += x * hg[r];
      ec[a] += x * homeAvg * att[h];
    }
    for (let t = 0; t < T; t++) {
      att[t] = (sc[t] + k) / (es[t] + k);
      def[t] = (co[t] + k) / (ec[t] + k);
    }
  }
  const attack = new Map<number, number>(), defense = new Map<number, number>(), played = new Map<number, number>();
  ids.forEach((id, t) => {
    attack.set(id, att[t]);
    defense.set(id, def[t]);
    played.set(id, playedRaw[t] ?? 0);
  });
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

/**
 * Modèle de production : saison en cours et saison précédente de la compétition, sans le poids
 * fixe de la v1.1 (la décroissance dans le temps s'en charge).
 */
export function runProductionModel(
  history: PlayedMatch[],
  prior: PlayedMatch[],
  homeId: number,
  awayId: number,
  kickoffAt: string,
): ModelResult {
  const all = [...prior, ...history].map((m) => ({ ...m, weight: 1 }));
  return runModel2(all, homeId, awayId, kickoffAt);
}
