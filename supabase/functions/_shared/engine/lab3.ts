// Laboratoire — expérience « Moteur 3.0 » (08/11/2026). Rien ici n'est utilisé en production :
// le module n'est appelé que par le mode `experiment` d'engine-evaluate, qui n'écrit rien.
//
// Variantes comparées sur EXACTEMENT les mêmes matchs que l'évaluation officielle :
//  A  — poisson-2.0 (production) : forces calculées dans la seule compétition.
//  B  — compétitions reliées : forces de chaque équipe calculées sur TOUS ses matchs (championnat,
//       coupes d'Europe et d'Afrique…), avec la moyenne de buts et l'avantage du terrain propres
//       à la compétition du match. Mêmes réglages que A (demi-vie, rétrécissement, poids 0,5 des
//       saisons précédentes).
//  +cal — recalibrage 1X2 « marche avant » : p_k^T, nul multiplié par e^d, renormalisé ; T et d
//       ajustés au début de chaque mois sur les seules prédictions des mois précédents.
//  Marché — pour les matchs dont la cote 1X2 a été relevée avant le coup d'envoi : probabilités
//       du marché (marge retirée) et mélanges modèle / marché.
// Seuls les matchs joués AVANT le jour du match sont utilisés. Fonctions pures.
import { marketProbabilities, type PlayedMatch, round } from "./poisson.ts";
import { DEFAULT_OPTIONS_2, dixonColesMatrix, fitStrengths, type Model2Options, runModel2FromStrengths } from "./poisson2.ts";

const DAY = 86400_000;
const EPS = 1e-12;
const clamp = (x: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, x));

export interface LabMatch extends PlayedMatch {
  id: number;
  competitionId: number;
  season: number;
}

export interface LabGroup {
  key: string;
  competitionId: number;
  season: number;
  matches: LabMatch[];
  /** Saison précédente de la compétition, déjà pondérée (comme l'évaluation officielle). */
  prior: PlayedMatch[];
}

// ---------------------------------------------------------------- variante B : forces globales

export interface GlobalStrengths {
  homeAvg: Map<number, number>;
  awayAvg: Map<number, number>;
  attack: Map<number, number>;
  defense: Map<number, number>;
}

/**
 * Forces globales : chaque match compte dans sa compétition (moyennes domicile / extérieur de la
 * compétition) et pour les deux équipes, quelle que soit la compétition.
 */
export function fitGlobalStrengths(
  history: (PlayedMatch & { competitionId: number })[],
  at: number,
  o: Model2Options = DEFAULT_OPTIONS_2,
  weightOf: (m: PlayedMatch & { competitionId: number }) => number = (m) => m.weight ?? 1,
): GlobalStrengths {
  const n = history.length;
  const w = new Float64Array(n);
  const comp = new Map<number, { w: number; h: number; a: number }>();
  for (let r = 0; r < n; r++) {
    const m = history[r];
    const age = Math.max(0, (at - Date.parse(m.kickoffAt)) / DAY);
    w[r] = weightOf(m) * 0.5 ** (age / o.halfLifeDays);
    const c = comp.get(m.competitionId) ?? { w: 0, h: 0, a: 0 };
    c.w += w[r];
    c.h += w[r] * m.homeGoals;
    c.a += w[r] * m.awayGoals;
    comp.set(m.competitionId, c);
  }
  const p = o.leaguePriorMatches;
  const homeAvg = new Map<number, number>(), awayAvg = new Map<number, number>();
  for (const [id, c] of comp) {
    homeAvg.set(id, (c.h + p * o.priorHomeGoals) / (c.w + p));
    awayAvg.set(id, (c.a + p * o.priorAwayGoals) / (c.w + p));
  }
  const index = new Map<number, number>();
  const idx = (id: number) => {
    let i = index.get(id);
    if (i === undefined) index.set(id, i = index.size);
    return i;
  };
  const hi = new Int32Array(n), ai = new Int32Array(n);
  const bh = new Float64Array(n), ba = new Float64Array(n);
  let goals = 0, weightSum = 0;
  for (let r = 0; r < n; r++) {
    const m = history[r];
    hi[r] = idx(m.homeId);
    ai[r] = idx(m.awayId);
    bh[r] = homeAvg.get(m.competitionId)!;
    ba[r] = awayAvg.get(m.competitionId)!;
    goals += w[r] * (bh[r] + ba[r]);
    weightSum += w[r];
  }
  const k = o.shrinkK * (weightSum > 0 ? goals / weightSum / 2 : (o.priorHomeGoals + o.priorAwayGoals) / 2);
  const T = index.size;
  const att = new Float64Array(T).fill(1), def = new Float64Array(T).fill(1);
  const sc = new Float64Array(T), es = new Float64Array(T), co = new Float64Array(T), ec = new Float64Array(T);
  for (let it = 0; it < o.iterations; it++) {
    sc.fill(0);
    es.fill(0);
    co.fill(0);
    ec.fill(0);
    for (let r = 0; r < n; r++) {
      const h = hi[r], a = ai[r], x = w[r];
      const m = history[r];
      sc[h] += x * m.homeGoals;
      es[h] += x * bh[r] * def[a];
      sc[a] += x * m.awayGoals;
      es[a] += x * ba[r] * def[h];
      co[h] += x * m.awayGoals;
      ec[h] += x * ba[r] * att[a];
      co[a] += x * m.homeGoals;
      ec[a] += x * bh[r] * att[h];
    }
    for (let t = 0; t < T; t++) {
      att[t] = (sc[t] + k) / (es[t] + k);
      def[t] = (co[t] + k) / (ec[t] + k);
    }
  }
  const attack = new Map<number, number>(), defense = new Map<number, number>();
  for (const [id, t] of index) {
    attack.set(id, att[t]);
    defense.set(id, def[t]);
  }
  return { homeAvg, awayAvg, attack, defense };
}

export function globalProbabilities(
  s: GlobalStrengths,
  competitionId: number,
  homeId: number,
  awayId: number,
  o: Model2Options = DEFAULT_OPTIONS_2,
): Record<string, number> {
  const h = s.homeAvg.get(competitionId) ?? o.priorHomeGoals;
  const a = s.awayAvg.get(competitionId) ?? o.priorAwayGoals;
  const lh = clamp(h * (s.attack.get(homeId) ?? 1) * (s.defense.get(awayId) ?? 1), 0.1, 5);
  const la = clamp(a * (s.attack.get(awayId) ?? 1) * (s.defense.get(homeId) ?? 1), 0.1, 5);
  return marketProbabilities(dixonColesMatrix(lh, la, o.rho, o.maxGoals));
}

// ---------------------------------------------------------------- recalibrage 1X2

export interface Calibration {
  t: number;
  d: number;
}

export const IDENTITY: Calibration = { t: 1, d: 0 };

export function calibrate(p: number[], c: Calibration): number[] {
  const q = p.map((x, k) => Math.max(x, EPS) ** c.t * (k === 1 ? Math.exp(c.d) : 1));
  const s = q.reduce((a, b) => a + b, 0);
  return q.map((x) => x / s);
}

/** T et d qui minimisent la perte logarithmique sur ces prédictions. */
export function fitCalibration(samples: { p: number[]; outcome: number }[], minSamples = 300): Calibration {
  if (samples.length < minSamples) return IDENTITY;
  const n = samples.length;
  const l0 = new Float64Array(n), l1 = new Float64Array(n), l2 = new Float64Array(n), lo = new Float64Array(n);
  const isDraw = new Uint8Array(n);
  samples.forEach((s, i) => {
    l0[i] = Math.log(Math.max(s.p[0], EPS));
    l1[i] = Math.log(Math.max(s.p[1], EPS));
    l2[i] = Math.log(Math.max(s.p[2], EPS));
    lo[i] = [l0[i], l1[i], l2[i]][s.outcome];
    isDraw[i] = s.outcome === 1 ? 1 : 0;
  });
  const loss = (t: number, d: number) => {
    let total = 0;
    for (let i = 0; i < n; i++) {
      const z = Math.exp(t * l0[i]) + Math.exp(t * l1[i] + d) + Math.exp(t * l2[i]);
      total -= t * lo[i] + (isDraw[i] ? d : 0) - Math.log(z);
    }
    return total;
  };
  // Descente par coordonnées, pas divisé par deux tant que rien ne s'améliore.
  let t = 1, d = 0, current = loss(t, d), step = 0.1;
  while (step >= 0.004) {
    let moved = false;
    for (const [dt, dd] of [[step, 0], [-step, 0], [0, step], [0, -step]]) {
      const nt = clamp(t + dt, 0.5, 2), nd = clamp(d + dd, -0.5, 0.5);
      const v = loss(nt, nd);
      if (v < current - 1e-9) {
        t = nt;
        d = nd;
        current = v;
        moved = true;
        break;
      }
    }
    if (!moved) step /= 2;
  }
  const best = { t: round(t, 3), d: round(d, 3) };
  return best;
}

// ---------------------------------------------------------------- mesures

class Metric {
  n = 0;
  brier = 0;
  logloss = 0;
  hits = 0;
  add(p: number[], outcome: number) {
    this.n++;
    p.forEach((x, i) => this.brier += (x - (i === outcome ? 1 : 0)) ** 2);
    this.logloss -= Math.log(Math.max(p[outcome], EPS));
    if (p.indexOf(Math.max(...p)) === outcome) this.hits++;
  }
  result() {
    const d = Math.max(this.n, 1);
    return {
      matches: this.n,
      brier: round(this.brier / d, 5),
      logloss: round(this.logloss / d, 5),
      accuracy: round(this.hits / d, 4),
    };
  }
}

class Bins {
  b = Array.from({ length: 10 }, () => [0, 0, 0]);
  add(p: number[], outcome: number) {
    p.forEach((x, k) => {
      const i = Math.min(9, Math.floor(x * 10));
      this.b[i][0]++;
      this.b[i][1] += x;
      this.b[i][2] += k === outcome ? 1 : 0;
    });
  }
  result() {
    return this.b.map(([n, sp, hits], i) => ({
      from: i / 10,
      count: n,
      predicted: n ? round(sp / n, 3) : 0,
      observed: n ? round(hits / n, 3) : 0,
    })).filter((x) => x.count > 0);
  }
}

interface Prediction {
  key: string;
  matchId: number;
  kickoffAt: string;
  homeGoals: number;
  awayGoals: number;
  base: number[];
  a: Record<string, number>;
  b: Record<string, number>;
  competitionId: number;
  season: number;
  homeId: number;
  awayId: number;
}

const x12 = (p: Record<string, number>) => [p["1X2.HOME"], p["1X2.DRAW"], p["1X2.AWAY"]];

/** Cotes 1X2 relevées avant le coup d'envoi → probabilités du marché, marge retirée. */
export function marketFromOdds(odds: { home: number; draw: number; away: number }): number[] | null {
  const inv = [odds.home, odds.draw, odds.away].map((o) => (o > 1 ? 1 / o : NaN));
  if (inv.some((x) => !Number.isFinite(x))) return null;
  const s = inv.reduce((a, b) => a + b, 0);
  return inv.map((x) => x / s);
}

export const blend = (model: number[], market: number[], marketWeight: number) =>
  model.map((p, k) => (1 - marketWeight) * p + marketWeight * market[k]);

/**
 * Expérience complète. `all` : tous les matchs terminés connus (toutes compétitions suivies),
 * pour la variante B. `odds` : cotes 1X2 du dernier relevé avant le coup d'envoi, par match.
 */
export function runExperiment(
  groups: LabGroup[],
  all: LabMatch[],
  odds: Map<number, { home: number; draw: number; away: number }> = new Map(),
  warmupMatches = 30,
  o: Model2Options = DEFAULT_OPTIONS_2,
) {
  const allSorted = [...all].sort((x, y) => x.kickoffAt.localeCompare(y.kickoffAt));
  // 1. Prédictions A et B, sur les matchs notés par l'évaluation officielle.
  const predictions: Prediction[] = [];
  for (const g of groups) {
    const sorted = [...g.matches].sort((x, y) => x.kickoffAt.localeCompare(y.kickoffAt));
    const priorAll = g.prior.map((p) => ({ ...p }));
    const byDay = new Map<string, ReturnType<typeof fitStrengths>>();
    const counts = [0, 0, 0];
    for (let i = 0; i < sorted.length; i++) {
      const m = sorted[i];
      let j = i;
      while (j > 0 && sorted[j - 1].kickoffAt === m.kickoffAt) j--;
      const history = sorted.slice(0, j);
      const outcome = m.homeGoals > m.awayGoals ? 0 : m.homeGoals === m.awayGoals ? 1 : 2;
      if (history.length >= warmupMatches) {
        const day = m.kickoffAt.slice(0, 10);
        let s = byDay.get(day);
        if (!s) {
          const before = [...priorAll, ...history.filter((h) => h.kickoffAt.slice(0, 10) < day)].map((h) => ({ ...h, weight: 1 }));
          s = fitStrengths(before, Date.parse(`${day}T00:00:00Z`), o);
          byDay.set(day, s);
        }
        const n = history.length;
        predictions.push({
          key: g.key,
          matchId: m.id,
          kickoffAt: m.kickoffAt,
          homeGoals: m.homeGoals,
          awayGoals: m.awayGoals,
          base: counts.map((c) => (c + 1) / (n + 3)),
          a: runModel2FromStrengths(s, m.homeId, m.awayId, o).probabilities,
          b: {},
          competitionId: g.competitionId,
          season: g.season,
          homeId: m.homeId,
          awayId: m.awayId,
        });
      }
      counts[outcome]++;
    }
  }
  predictions.sort((x, y) => x.kickoffAt.localeCompare(y.kickoffAt));

  // Variante B : forces reliées calculées au lundi 00:00 (UTC) de la semaine du match, avec les
  // seuls matchs antérieurs ; une semaine à la fois, rien n'est gardé en mémoire ensuite.
  const weekStart = (iso: string) => {
    const t = Date.parse(`${iso.slice(0, 10)}T00:00:00Z`);
    const dow = (new Date(t).getUTCDay() + 6) % 7;
    return new Date(t - dow * DAY).toISOString();
  };
  const byWeek = new Map<string, Prediction[]>();
  for (const p of predictions) {
    const k = `${weekStart(p.kickoffAt)}|${p.season}`;
    (byWeek.get(k) ?? byWeek.set(k, []).get(k)!).push(p);
  }
  let cut = 0;
  for (const k of [...byWeek.keys()].sort()) {
    const [at, seasonText] = k.split("|");
    const season = Number(seasonText);
    while (cut < allSorted.length && allSorted[cut].kickoffAt < at) cut++;
    const s = fitGlobalStrengths(allSorted.slice(0, cut), Date.parse(at), o, (m) => ((m as LabMatch).season < season ? 0.5 : 1));
    for (const p of byWeek.get(k)!) p.b = globalProbabilities(s, p.competitionId, p.homeId, p.awayId, o);
  }

  // 2. Recalibrage marche avant : réglages refaits au début de chaque mois.
  const calA = new Map<string, Calibration>(), calB = new Map<string, Calibration>();
  const monthOf = (k: string) => k.slice(0, 7);
  for (const month of [...new Set(predictions.map((p) => monthOf(p.kickoffAt)))]) {
    const past = predictions.filter((p) => monthOf(p.kickoffAt) < month);
    const outcomeOf = (p: Prediction) => (p.homeGoals > p.awayGoals ? 0 : p.homeGoals === p.awayGoals ? 1 : 2);
    calA.set(month, fitCalibration(past.map((p) => ({ p: x12(p.a), outcome: outcomeOf(p) }))));
    calB.set(month, fitCalibration(past.map((p) => ({ p: x12(p.b), outcome: outcomeOf(p) }))));
  }

  // 3. Mesures.
  const variants = ["baseline", "A", "B", "A+cal", "B+cal"] as const;
  type V = typeof variants[number];
  const m1x2 = Object.fromEntries(variants.map((v) => [v, new Metric()])) as Record<V, Metric>;
  const mDnb = Object.fromEntries(variants.map((v) => [v, new Metric()])) as Record<V, Metric>;
  const bins = Object.fromEntries(variants.map((v) => [v, new Bins()])) as Record<V, Bins>;
  const goals = { A: { ou: new Metric(), btts: new Metric() }, B: { ou: new Metric(), btts: new Metric() } };
  const perComp: Record<string, Record<V, Metric>> = {};
  const marketWeights = [0, 0.3, 0.5, 0.7, 0.85, 1];
  const market: Record<string, Metric> = {};
  const mk = (name: string) => (market[name] ??= new Metric());

  for (const p of predictions) {
    const outcome = p.homeGoals > p.awayGoals ? 0 : p.homeGoals === p.awayGoals ? 1 : 2;
    const month = monthOf(p.kickoffAt);
    const probs: Record<V, number[]> = {
      baseline: p.base,
      A: x12(p.a),
      B: x12(p.b),
      "A+cal": calibrate(x12(p.a), calA.get(month)!),
      "B+cal": calibrate(x12(p.b), calB.get(month)!),
    };
    perComp[p.key] ??= Object.fromEntries(variants.map((v) => [v, new Metric()])) as Record<V, Metric>;
    for (const v of variants) {
      m1x2[v].add(probs[v], outcome);
      bins[v].add(probs[v], outcome);
      perComp[p.key][v].add(probs[v], outcome);
      if (outcome !== 1) {
        const q = probs[v];
        mDnb[v].add([q[0] / (q[0] + q[2]), q[2] / (q[0] + q[2])], outcome === 0 ? 0 : 1);
      }
    }
    const over = p.homeGoals + p.awayGoals > 2.5 ? 0 : 1;
    const btts = p.homeGoals > 0 && p.awayGoals > 0 ? 0 : 1;
    for (const [name, q] of [["A", p.a], ["B", p.b]] as const) {
      goals[name].ou.add([q["OU.OVER.2.5"], 1 - q["OU.OVER.2.5"]], over);
      goals[name].btts.add([q["BTTS.YES"], 1 - q["BTTS.YES"]], btts);
    }
    const o1x2 = odds.get(p.matchId);
    const mkt = o1x2 ? marketFromOdds(o1x2) : null;
    if (mkt) {
      for (const w of marketWeights) {
        mk(`A+cal / marché ${w}`).add(blend(probs["A+cal"], mkt, w), outcome);
        mk(`B+cal / marché ${w}`).add(blend(probs["B+cal"], mkt, w), outcome);
      }
    }
  }

  const res = (r: Record<V, Metric>) => Object.fromEntries(variants.map((v) => [v, r[v].result()]));
  const lastMonth = monthOf(predictions.at(-1)?.kickoffAt ?? "");
  return {
    matches: predictions.length,
    oneXTwo: res(m1x2),
    dnb: res(mDnb),
    goals: {
      over_2_5: { A: goals.A.ou.result(), B: goals.B.ou.result() },
      btts: { A: goals.A.btts.result(), B: goals.B.btts.result() },
    },
    calibration: Object.fromEntries(variants.filter((v) => v !== "baseline").map((v) => [v, bins[v].result()])),
    calibration_settings_latest: { A: calA.get(lastMonth), B: calB.get(lastMonth) },
    per_competition_logloss: Object.fromEntries(
      Object.entries(perComp).map(([k, r]) => [k, {
        matches: r.A.n,
        ...Object.fromEntries(variants.map((v) => [v, r[v].result().logloss])),
      }]),
    ) as Record<string, { matches: number } & Record<V, number>>,
    market: Object.fromEntries(Object.entries(market).map(([k, v]) => [k, v.result()])),
  };
}
