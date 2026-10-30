// Outils du Laboratoire IA (fonctions pures) : simulation, comparaison, alternatives.
// Tout est calculé à partir des probabilités du modèle ; les simulations sont étiquetées comme
// telles et ne prédisent aucun résultat réel.
import type { CouponLine } from "../assistant/actions.ts";
import { fragility } from "../assistant/actions.ts";
import { type Candidate, outcomeLabel, qualityFamilyOf } from "../coupons/generator.ts";

const round = (x: number, d = 4) => Math.round(x * 10 ** d) / 10 ** d;

/** Loi du nombre de sélections justes (Poisson-binomiale), sélections supposées indépendantes. */
export function correctCountDistribution(probabilities: number[]): number[] {
  let dist = [1];
  for (const p of probabilities) {
    const next = new Array(dist.length + 1).fill(0);
    dist.forEach((q, k) => {
      next[k] += q * (1 - p);
      next[k + 1] += q * p;
    });
    dist = next;
  }
  return dist.map((x) => round(x));
}

/** Générateur pseudo-aléatoire reproductible (mulberry32). */
export function seeded(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export interface Simulation {
  label: string;
  runs: number;
  probability_all_correct: number;
  distribution: number[];
  expected_correct: number;
  simulated_wins: number;
  /** Fourchette (95 %) du nombre de coupons gagnants sur `runs` tirages. */
  wins_interval: [number, number];
  /** Retour moyen pour 1 misé si tous les coupons étaient joués (cote × probabilité du modèle). */
  model_return_per_unit: number;
}

export function simulate(probabilities: number[], totalOdd: number, runs = 1000, seed = 42): Simulation {
  const rand = seeded(seed);
  let wins = 0;
  for (let r = 0; r < runs; r++) {
    if (probabilities.every((p) => rand() < p)) wins++;
  }
  const pAll = probabilities.reduce((x, p) => x * p, 1);
  const sd = Math.sqrt(runs * pAll * (1 - pAll));
  const dist = correctCountDistribution(probabilities);
  return {
    label: `Simulation : ${runs} coupons tirés au hasard selon les probabilités du modèle. Ce n'est pas un résultat réel ni une prévision de gain.`,
    runs,
    probability_all_correct: round(pAll),
    distribution: dist,
    expected_correct: round(probabilities.reduce((s, p) => s + p, 0), 2),
    simulated_wins: wins,
    wins_interval: [Math.max(0, Math.round(runs * pAll - 1.96 * sd)), Math.min(runs, Math.round(runs * pAll + 1.96 * sd))],
    model_return_per_unit: round(pAll * totalOdd, 3),
  };
}

export interface CouponSummaryLine {
  id: string;
  title: string;
  lines: CouponLine[];
}

export interface Comparison {
  id: string;
  title: string;
  selections: number;
  total_odd: number;
  combined_probability: number;
  implied_probability: number | null;
  model_minus_market: number | null;
  competitions: number;
  diversification: number;
  correlated_pairs: number;
  low_reliability: number;
  unvalidated_markets: number;
  weakest: string | null;
}

/** Indicateurs comparables entre coupons (cote, probabilités, diversification, corrélations, données). */
export function compareCoupons(coupons: CouponSummaryLine[], beatsBaseline: Record<string, boolean> | null): Comparison[] {
  return coupons.map((c) => {
    const lines = c.lines;
    const total = round(lines.reduce((x, l) => x * l.odd, 1), 2);
    const p = round(lines.reduce((x, l) => x * l.modelProbability, 1));
    const implied = lines.every((l) => l.impliedProbability !== null)
      ? round(lines.reduce((x, l) => x * (l.impliedProbability as number), 1))
      : null;
    const competitions = new Set(lines.map((l) => l.competition)).size;
    let correlated = 0;
    for (let i = 0; i < lines.length; i++) {
      for (let j = i + 1; j < lines.length; j++) {
        if (lines[i].competition === lines[j].competition && lines[i].kickoffAt.slice(0, 10) === lines[j].kickoffAt.slice(0, 10)) correlated++;
      }
    }
    const weakest = [...lines].sort((a, b) => fragility(b) - fragility(a))[0];
    return {
      id: c.id,
      title: c.title,
      selections: lines.length,
      total_odd: total,
      combined_probability: p,
      implied_probability: implied,
      model_minus_market: implied === null ? null : round(p - implied),
      competitions,
      diversification: lines.length ? round(competitions / lines.length, 2) : 0,
      correlated_pairs: correlated,
      low_reliability: lines.filter((l) => l.reliability === "faible").length,
      unvalidated_markets: lines.filter((l) => beatsBaseline?.[qualityFamilyOf(l.key)] === false).length,
      weakest: weakest ? `${outcomeLabel(weakest.key, weakest.home, weakest.away)} (${weakest.home} – ${weakest.away})` : null,
    };
  });
}

export interface Alternative {
  replace_position: number;
  replaced: string;
  match_id: number;
  key: string;
  selection: string;
  match: string;
  odd: number;
  model_probability: number;
  edge: number | null;
  new_total_odd: number;
  new_combined_probability: number;
  kind: "meme_match" | "autre_match";
}

/**
 * Optimisation : pour les sélections les plus fragiles, alternatives plus probables selon le modèle
 * (autre issue du même match, ou autre match de cote voisine), avec la cote et la probabilité
 * du coupon après remplacement. L'utilisateur choisit.
 */
export function alternativesFor(lines: CouponLine[], candidates: Candidate[], howMany = 2, perLine = 3): Alternative[] {
  const used = new Set(lines.map((l) => l.matchId));
  const total = lines.reduce((x, l) => x * l.odd, 1);
  const pAll = lines.reduce((x, l) => x * l.modelProbability, 1);
  const out: Alternative[] = [];
  for (const l of [...lines].sort((a, b) => fragility(b) - fragility(a)).slice(0, howMany)) {
    const sameMatch = candidates.filter((c) => c.matchId === l.matchId && c.key !== l.key && c.modelProbability > l.modelProbability + 0.03);
    const otherMatch = candidates.filter((c) =>
      !used.has(c.matchId) && c.odd >= l.odd * 0.8 && c.odd <= l.odd * 1.25 && c.modelProbability > l.modelProbability + 0.03 &&
      (c.edge ?? 0) <= 0.1 && c.reliability !== "faible"
    );
    const pick = [
      ...sameMatch.sort((a, b) => b.modelProbability - a.modelProbability).slice(0, 1).map((c) => ({ c, kind: "meme_match" as const })),
      ...otherMatch.sort((a, b) => b.modelProbability - a.modelProbability).slice(0, perLine).map((c) => ({ c, kind: "autre_match" as const })),
    ].slice(0, perLine);
    for (const { c, kind } of pick) {
      out.push({
        replace_position: l.position,
        replaced: `${outcomeLabel(l.key, l.home, l.away)} (${l.home} – ${l.away})`,
        match_id: c.matchId,
        key: c.key,
        selection: outcomeLabel(c.key, c.home, c.away),
        match: `${c.home} – ${c.away}`,
        odd: c.odd,
        model_probability: c.modelProbability,
        edge: c.edge,
        new_total_odd: round((total / l.odd) * c.odd, 2),
        new_combined_probability: round((pAll / l.modelProbability) * c.modelProbability),
        kind,
      });
    }
  }
  return out;
}
